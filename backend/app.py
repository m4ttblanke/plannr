from fastapi import FastAPI, File, UploadFile, Query, Body, Request
from fastapi.responses import JSONResponse, RedirectResponse, StreamingResponse, HTMLResponse
import stripe
from google import genai
from google.genai import types as genai_types
from google.genai import errors as genai_errors
from PyPDF2 import PdfReader
import asyncio
import time
import secrets
import hashlib
import hmac
import base64
import csv
import io
import json
import logging
from io import BytesIO
from datetime import date as date_type
from icalendar import Calendar as ICalendar, Event as ICalEvent
from google_auth_oauthlib.flow import Flow
from google.oauth2.credentials import Credentials
from google.auth.exceptions import RefreshError
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from pydantic import BaseModel
from typing import List, Optional
from pdf2image import convert_from_bytes
import pytesseract
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from config import settings
from repositories.user_repository import initialize, get_google_credentials, upsert_google_credentials, delete_user


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("plannr")


def _mask_email(email: Optional[str]) -> str:
    """Redact an email for logs: 'student@example.com' -> 's***@example.com'."""
    if not email or "@" not in email:
        return "<none>"
    local, _, domain = email.partition("@")
    return f"{(local[:1] or '')}***@{domain}"


# Upload guardrails: a single large PDF (or a malicious upload) is read fully
# into memory and, for scanned pages, rasterized at 200 DPI for OCR — both are
# easy ways to exhaust a small dyno. Reject early instead.
MAX_SYLLABUS_BYTES = 10 * 1024 * 1024  # 10 MB
MAX_OCR_PAGES = 30


class CalendarEvent(BaseModel):
    title: str
    date: str
    description: Optional[str] = ""
    type: Optional[str] = "other"


class CalendarSyncRequest(BaseModel):
    events: List[CalendarEvent]


class GeminiSyllabusEvent(BaseModel):
    title: str
    date: str
    type: str
    description: str
    Class: str = "Unknown"
    isSyllabus: bool = True


class GeminiSyllabusResult(BaseModel):
    events: List[GeminiSyllabusEvent]


class SyncEventRequest(BaseModel):
    local_id: str
    title: str
    date: str
    description: Optional[str] = ""
    type: Optional[str] = "other"
    google_event_id: Optional[str] = None
    is_deleted: bool = False


class CalendarClassSyncRequest(BaseModel):
    class_name: str
    google_calendar_id: Optional[str] = None
    events: List[SyncEventRequest]
    background_color: Optional[str] = None  # Hex color for calendar background (e.g., "#FF5733")
    foreground_color: Optional[str] = None  # Hex color for text (e.g., "#FFFFFF")
    reminder_minutes: Optional[int] = None  # Minutes before an event to remind; None = Google's default reminders

# Gemini client — None if key not configured
_gemini_client = genai.Client(api_key=settings.gemini_api_key) if settings.gemini_api_key else None

_stripe_client = stripe.StripeClient(settings.stripe_secret_key) if settings.stripe_secret_key else None

SCOPES = [
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/calendar.events',
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
    'openid'
]

# OAuth "state" is a signed, self-contained token rather than a server-side
# session: the PKCE code_verifier and an issue timestamp are packed into the
# state parameter itself and HMAC-signed with a key derived from the Google
# client secret. This survives dyno restarts and redeploys (an in-memory store
# does not) and needs no database round-trip. A signed token is not single-use,
# but replay is harmless here — Google enforces single use of the auth `code`,
# which is the value that actually grants access.
OAUTH_STATE_TTL = 300  # 5 minutes


def _oauth_state_key() -> bytes:
    return hashlib.sha256(
        (settings.google_client_secret or "plannr-dev-secret").encode()
    ).digest()


def _b64u(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def _b64u_decode(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def issue_oauth_state(code_verifier: str) -> str:
    """Pack the PKCE verifier + timestamp into a signed, URL-safe state token."""
    body = _b64u(json.dumps(
        {"cv": code_verifier, "ts": int(time.time())}, separators=(",", ":")
    ).encode())
    sig = _b64u(hmac.new(_oauth_state_key(), body.encode(), hashlib.sha256).digest())
    return f"{body}.{sig}"


def verify_oauth_state(state: str) -> Optional[str]:
    """Return the code_verifier if `state` is well-formed, correctly signed and
    unexpired; otherwise None."""
    if not state or state.count(".") != 1:
        return None
    body, sig = state.split(".", 1)
    expected = _b64u(hmac.new(_oauth_state_key(), body.encode(), hashlib.sha256).digest())
    if not hmac.compare_digest(expected, sig):
        return None
    try:
        data = json.loads(_b64u_decode(body))
        code_verifier, ts = str(data["cv"]), int(data["ts"])
    except (ValueError, KeyError, TypeError):
        return None
    if time.time() - ts > OAUTH_STATE_TTL:
        return None
    return code_verifier


# Verify database connectivity at startup, but don't take the whole app down if
# the database is briefly unreachable (Render's free Postgres sleeps/restarts
# too). pool_pre_ping on the engine recovers connections per-request once it's back.
try:
    initialize()
except Exception:
    logger.warning(
        "Database not reachable at startup; continuing and retrying per-request",
        exc_info=True,
    )

app = FastAPI(
    title='Plannr API',
    description='Upload your syllabus, the API parses it and uploads the relevant time slots to your Google Calendar'
)

# Per-IP rate limiting. Requires uvicorn to be run with --proxy-headers so
# request.client.host reflects the real client IP behind Render's proxy
# rather than the proxy's own address (see render.yaml).
limiter = Limiter(key_func=get_remote_address, default_limits=["100/minute"])
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(SlowAPIMiddleware)


def get_oauth_flow():
    """Create OAuth flow from settings."""
    client_config = {
        "web": {
            "client_id": settings.google_client_id,
            "client_secret": settings.google_client_secret,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": [settings.google_redirect_uri],
        }
    }
    flow = Flow.from_client_config(client_config, scopes=SCOPES)
    flow.redirect_uri = settings.google_redirect_uri
    return flow


def _build_credentials(creds_data: dict) -> Credentials:
    """Reconstruct a Google Credentials object from a stored credentials dict."""
    return Credentials(
        token=creds_data.get("token"),
        refresh_token=creds_data.get("refresh_token"),
        token_uri=creds_data.get("token_uri"),
        client_id=settings.google_client_id,
        client_secret=settings.google_client_secret,
        scopes=creds_data.get("scopes"),
    )


@app.get('/auth/google', tags=['OAuth'])
@limiter.limit("10/minute")
async def google_auth(request: Request):
    """Start OAuth flow - redirects to Google sign-in"""
    if not settings.google_client_id or not settings.google_client_secret:
        return JSONResponse(
            status_code=500,
            content={"error": "Google OAuth credentials not configured. Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in .env"}
        )

    code_verifier = secrets.token_urlsafe(96)
    code_challenge = base64.urlsafe_b64encode(
        hashlib.sha256(code_verifier.encode()).digest()
    ).rstrip(b"=").decode()
    state = issue_oauth_state(code_verifier)

    flow = get_oauth_flow()
    authorization_url, _ = flow.authorization_url(
        access_type='offline',
        include_granted_scopes='true',
        prompt='consent',
        state=state,
        code_challenge=code_challenge,
        code_challenge_method='S256',
    )
    return RedirectResponse(url=authorization_url)


@app.get('/auth/callback', tags=['OAuth'])
@limiter.limit("10/minute")
async def auth_callback(request: Request, code: str = Query(...), state: str = Query(None), redirect_to_app: bool = Query(True)):
    """Handle OAuth callback from Google"""
    try:
        # Validate the signed OAuth state parameter to prevent CSRF attacks
        from urllib.parse import quote as _quote
        code_verifier = verify_oauth_state(state)
        if not code_verifier:
            error_url = f"plannr://auth/callback?error={_quote('Invalid or expired sign-in session. Please try signing in again.')}"
            return RedirectResponse(url=error_url)

        flow = get_oauth_flow()
        flow.fetch_token(code=code, code_verifier=code_verifier)

        credentials = flow.credentials

        # Get user info
        from googleapiclient.discovery import build
        user_info_service = build('oauth2', 'v2', credentials=credentials)
        user_info = user_info_service.userinfo().get().execute()
        email = user_info.get('email')
        name = user_info.get('name', '')
        picture = user_info.get('picture', '')

        # Store credentials — client_id/secret come from settings, not storage
        creds_data = {
            'token': credentials.token,
            'refresh_token': credentials.refresh_token,
            'token_uri': credentials.token_uri,
            'scopes': list(credentials.scopes or []),
        }

        upsert_google_credentials(email, creds_data)

        # Redirect to iOS app with custom URL scheme
        from urllib.parse import quote
        app_callback_url = f"plannr://auth/callback?email={quote(email)}&name={quote(name)}&picture={quote(picture)}"
        return RedirectResponse(url=app_callback_url)

    except Exception as e:
        logger.exception("OAuth callback error")
        # Redirect to app with error
        from urllib.parse import quote
        error_url = f"plannr://auth/callback?error={quote(str(e))}"
        return RedirectResponse(url=error_url)


@app.get('/me', tags=['OAuth'])
@limiter.limit("30/minute")
async def get_me(request: Request, email: str = Query(...)):
    """Re-fetch current Google profile info (name, picture) for an already-linked
    account. Lets the app backfill/refresh the profile photo for sessions that
    predate this field, without requiring a full sign-out/sign-in."""
    creds_data = get_google_credentials(email)
    if not creds_data:
        return JSONResponse(status_code=401, content={"error": "User not authenticated."})
    try:
        user_info_service = build('oauth2', 'v2', credentials=_build_credentials(creds_data))
        user_info = user_info_service.userinfo().get().execute()
        return JSONResponse(status_code=200, content={
            "email": user_info.get('email', email),
            "name": user_info.get('name', ''),
            "picture": user_info.get('picture', ''),
        })
    except RefreshError:
        return JSONResponse(status_code=401, content={
            "error": "Google access was revoked or expired. Please sign in again."
        })
    except Exception as e:
        return JSONResponse(status_code=400, content={"error": f"Failed to fetch profile: {e}"})


@app.delete('/account', tags=['OAuth'])
@limiter.limit("5/minute")
async def delete_account(request: Request, email: str = Query(...)):
    """Delete a user's account record and stored Google OAuth credentials.

    Returns 200 only when the deletion actually committed (or the user did not
    exist — `delete_user` is a no-op in that case). A DB failure returns 500 so
    the client does not wipe local state while server-side data still exists.
    """
    try:
        delete_user(email)
    except Exception:
        logger.exception("Account deletion failed for %s", _mask_email(email))
        return JSONResponse(
            status_code=500,
            content={"error": "Could not delete your account right now. Please try again."}
        )
    return JSONResponse(status_code=200, content={"message": "Account deleted."})


@app.post('/syllabus', tags=['Plannr'])
@limiter.limit("10/minute")
async def parse_syllabus(request: Request, file: UploadFile = File(...)):
    try:
        logger.info("Syllabus upload received (filename=%s)", file.filename)

        # Read the uploaded file
        contents = await file.read()
        if len(contents) > MAX_SYLLABUS_BYTES:
            return JSONResponse(
                status_code=413,
                content={"error": (
                    f"That file is {len(contents) // (1024 * 1024)} MB. "
                    f"Please upload a syllabus under {MAX_SYLLABUS_BYTES // (1024 * 1024)} MB."
                )}
            )
        logger.info("Syllabus size: %d bytes", len(contents))

        # Extract text from PDF
        pdf_text = extract_text_from_pdf(contents)
        logger.info("Extracted %d characters of syllabus text", len(pdf_text))

        if not pdf_text:
            return JSONResponse(
                status_code=400,
                content={"error": "Could not extract text from PDF"}
            )

        # Send to Gemini for parsing
        parsed_events = await parse_with_gemini(pdf_text)
        logger.info("Parsed %d events from syllabus", len(parsed_events.get('events', [])))

        return JSONResponse(
            status_code=200,
            content={
                "message": "Syllabus received and parsed",
                "filename": file.filename,
                "size": len(contents),
                "events": parsed_events.get('events', [])
            }
        )
    except Exception as e:
        logger.exception("Error handling /syllabus upload")
        return JSONResponse(
            status_code=400,
            content={"error": str(e)}
        )


def extract_text_from_pdf(pdf_bytes: bytes) -> str:
    """Extract text from PDF bytes. Falls back to OCR for scanned/image PDFs."""
    try:
        pdf_file = BytesIO(pdf_bytes)
        pdf_reader = PdfReader(pdf_file)
        text = ""
        for page in pdf_reader.pages:
            text += page.extract_text() or ""

        if text.strip():
            logger.info("PyPDF2 extracted %d characters", len(text))
            return text

        logger.info("No embedded text found, falling back to OCR")
        return extract_text_via_ocr(pdf_bytes)

    except Exception:
        logger.exception("PDF text extraction failed, falling back to OCR")
        return extract_text_via_ocr(pdf_bytes)


def extract_text_via_ocr(pdf_bytes: bytes) -> str:
    """OCR fallback for scanned/image-based PDFs."""
    try:
        from pdf2image import convert_from_bytes
        import pytesseract

        images = convert_from_bytes(pdf_bytes, dpi=200)
        if len(images) > MAX_OCR_PAGES:
            logger.warning("OCR: capping %d-page PDF at %d pages", len(images), MAX_OCR_PAGES)
            images = images[:MAX_OCR_PAGES]
        logger.info("OCR: processing %d page(s)", len(images))

        text = ""
        for image in images:
            text += pytesseract.image_to_string(image) + "\n"

        logger.info("OCR extracted %d characters", len(text))
        return text

    except Exception:
        logger.exception("OCR failed")
        return ""

class SyllabusParsingError(Exception):
    """Raised when Gemini fails to produce a usable response — kept distinct from
    a legitimate zero-events result so callers don't silently show "no events found"
    for what was actually an API or parsing failure."""
    pass


# Gemini status codes worth retrying — both are transient capacity issues on
# Google's end (503 UNAVAILABLE, 429 RESOURCE_EXHAUSTED) that typically clear
# up within seconds, unlike a 400/401/etc which will just fail the same way again.
GEMINI_RETRYABLE_CODES = {503, 429}
GEMINI_MAX_ATTEMPTS = 3


async def parse_with_gemini(syllabus_text: str) -> dict:
    """Use Gemini to extract calendar events from syllabus text"""
    if not _gemini_client:
        raise SyllabusParsingError("Gemini API key not configured on the server.")

    prompt = f"""
        You are an AI assistant that parses university course syllabi into a structured list of **graded deliverables**. The user has provided the full syllabus text. Your job is to accurately extract **what is due**, **when it is due**, and **how it should be labeled**, using careful temporal and contextual reasoning.

Your primary objective is **correct due-date inference**, even when dates are implicit, relative, or described indirectly.

Firstly, ensure the uploaded document is a syllabus for a university course. If it does not appear to be a syllabus, respond with an error message stating such in the JSON output. 
If not a syllabus, make the "isSyllabus" field to FALSE. If it is a syllabus, this field should be TRUE. Do NOT attempt to extract events if the document is not a syllabus.
---

## Step 1: Academic Term & Year Inference (MANDATORY)

Before extracting any events, you must infer:
- **Academic year** (e.g., 2024–2025, 2025–2026)
- **Quarter** (Fall, Winter, or Spring)

You must infer the year from:
- Explicit years in syllabus ("Winter 2025", "Spring 2024")  
- Headers/footers with year info
- Default to 2026 if no year found

Academic year consistency is critical - all dates must use the same year.

---

## Step 2: Quarter Start Date Inference

After determining the **quarter and year**, infer the **first instructional day** using standard university quarter conventions:

- **Winter Quarter**: early January
- **Spring Quarter**: late March or early April
- **Fall Quarter**: late September

If the syllabus explicitly states:
- “Week 1”
- “Classes begin on …”
- “Instruction starts …”

Use that as the authoritative anchor.

If not explicitly stated:
- Assume **Week 1 begins on the first Monday of the quarter’s instructional period**
- Use that date as the anchor for all week-based calculations

---

## Step 3: Temporal Reasoning Rules (CRITICAL)

You must resolve dates using simple, clear rules:

**Week Calculations:**
- Find "Week 1" start in syllabus or assume first Monday of quarter
- Week N = Start + (N-1) weeks
- "Week 3 Friday" = Friday of third week

**Common Patterns:**
- "Every Monday" = all Mondays in quarter
- "Finals Week" = standard finals period  
- "Mid-February" = Feb 15th
- Specific dates like "Dec 12" = add year (2026)

Examples:
- “Homework due at the end of lecture each week”
- “Lab due by the end of section”
- “Quiz every Friday”
- “Assignments due weekly”
- “Final exam during finals week”

If you can't calculate a date confidently, skip that event.

## Step 4: What to Extract

Extract ONLY graded or required deliverables:
- Homework assignments
- Labs
- Quizzes
- Midterms
- Final exams
- Projects, reports, checkpoints

Ignore:
- General policies
- Grading breakdowns
- Office hours
- Lectures or readings (unless graded)

---

## Step 5: Titles and Naming Discipline

- Preserve **canonical titles exactly as written**:
  - `HW1`, `Homework 3`, `Lab 2`, `Midterm 1`, `Final Exam`
- Do NOT invent names or normalize aggressively
- If an assignment has multiple graded submissions (draft/final, submission/regrade):
  - Create **separate events** with clear titles
- Be sure to take note of what the name of the course is that the student is taking ot output. Typically, this will be in the title, header, footer, etc. 
If none is found just put unknown DO not put error in that field. If available call the course by it's known name, such as CS101 as opposed to Computer Science Basics. 
Course codes over long wordy stuff.



---

## Step 6: Tables and Weekly Schedules

- Carefully inspect tables, calendars, and week-by-week schedules
- If a week lists **any due work**, extract it
- Assume items listed in structured schedules are graded unless explicitly stated otherwise

---

## Output Format (STRICT)

Return a **single JSON object** in this exact format:
        {{
            "events": [
                {{
                    "title": "event name",
                    "date": "YYYY-MM-DD",
                    "type": "homework/exam/quiz/lab/other",
                    "description": "brief description",
                    "Class": "The name of the class the user is taking here",
                    "isSyllabus": true
                }}
            ]
        }}
        
        Syllabus:
        {syllabus_text}
        """
        
    response = None
    for attempt in range(1, GEMINI_MAX_ATTEMPTS + 1):
        try:
            response = _gemini_client.models.generate_content(
                model='gemini-3.7-flash',
                contents=prompt,
                config=genai_types.GenerateContentConfig(
                    temperature=0.1,
                    top_p=0.8,
                    top_k=40,
                    max_output_tokens=8192,
                    response_mime_type='application/json',
                    response_schema=GeminiSyllabusResult,
                ),
            )
            break
        except genai_errors.APIError as e:
            is_retryable = e.code in GEMINI_RETRYABLE_CODES
            if not is_retryable or attempt == GEMINI_MAX_ATTEMPTS:
                logger.error("Gemini API error (attempt %d/%d): %s",
                             attempt, GEMINI_MAX_ATTEMPTS, e)
                raise SyllabusParsingError(f"Gemini API call failed: {e}") from e
            wait_seconds = 2 ** (attempt - 1)  # 1s, 2s, 4s
            logger.warning("Gemini %s %s — retrying in %ds (attempt %d/%d)",
                           e.code, e.status, wait_seconds, attempt, GEMINI_MAX_ATTEMPTS)
            await asyncio.sleep(wait_seconds)
        except Exception as e:
            logger.exception("Unexpected error calling Gemini")
            raise SyllabusParsingError(f"Gemini API call failed: {e}") from e

    response_text = response.text
    logger.debug("Gemini raw response: %s", response_text)

    # Look for JSON in the response
    start_idx = response_text.find('{')
    end_idx = response_text.rfind('}') + 1
    if start_idx == -1 or end_idx <= start_idx:
        logger.warning("No JSON object found in Gemini response")
        raise SyllabusParsingError("Gemini did not return a parseable response. Please try again.")

    json_str = response_text[start_idx:end_idx]

    try:
        parsed = json.loads(json_str)
    except json.JSONDecodeError as e:
        # Most often caused by the response getting cut off at max_output_tokens
        # before the JSON finished — check finish_reason to give a specific message.
        finish_reason = None
        try:
            finish_reason = response.candidates[0].finish_reason
        except Exception:
            pass
        logger.warning("Gemini JSON decode failed (finish_reason=%s)", finish_reason)
        if finish_reason and 'MAX_TOKENS' in str(finish_reason):
            raise SyllabusParsingError(
                "This syllabus has too many events for Plannr to parse in one pass. "
                "Try splitting it into smaller uploads."
            ) from e
        raise SyllabusParsingError("Gemini's response was malformed. Please try again.") from e

    logger.info("Gemini returned %d events",
                len(parsed.get("events", [])) if isinstance(parsed, dict) else 0)
    return parsed


def _find_or_create_calendar(service, class_name: str, background_color: Optional[str] = None, foreground_color: Optional[str] = None) -> str:
    """Find a secondary calendar by name, or create one with custom colors. Returns the calendar ID."""
    calendar_list = service.calendarList().list().execute()
    for cal in calendar_list.get('items', []):
        if cal.get('summary') == class_name:
            # If colors are provided and calendar exists, update colors
            if background_color or foreground_color:
                _set_calendar_colors(service, cal['id'], background_color, foreground_color)
            return cal['id']
    
    # Not found — create a new secondary calendar
    new_cal = service.calendars().insert(body={'summary': class_name}).execute()
    calendar_id = new_cal['id']
    
    # Step 2: Set colors if provided (two-step process required by Google Calendar API)
    if background_color or foreground_color:
        _set_calendar_colors(service, calendar_id, background_color, foreground_color)
    
    return calendar_id


def _set_calendar_colors(service, calendar_id: str, background_color: Optional[str] = None, foreground_color: Optional[str] = None) -> None:
    """Set custom colors for a calendar using the calendarList PATCH endpoint."""
    try:
        # Build the color update body
        color_body = {}
        if background_color:
            # Ensure hex color format
            if not background_color.startswith('#'):
                background_color = f"#{background_color}"
            color_body['backgroundColor'] = background_color
        
        if foreground_color:
            # Ensure hex color format
            if not foreground_color.startswith('#'):
                foreground_color = f"#{foreground_color}"
            color_body['foregroundColor'] = foreground_color
        
        if color_body:
            # PATCH the calendarList entry with colorRgbFormat=true to enable custom hex colors
            service.calendarList().patch(
                calendarId=calendar_id,
                body=color_body,
                colorRgbFormat=True  # Critical: enables custom hex colors
            ).execute()

            logger.info("Set colors for calendar %s", calendar_id)
    except Exception:
        # Don't fail the entire operation if color setting fails
        logger.warning("Failed to set calendar colors", exc_info=True)


def _build_google_event_body(event: SyncEventRequest, reminder_minutes: Optional[int] = None) -> dict:
    body = {
        'summary': event.title,
        'description': event.description or '',
        'start': {'date': event.date},
        'end': {'date': event.date},
    }
    if reminder_minutes is not None:
        body['reminders'] = {
            'useDefault': False,
            'overrides': [{'method': 'popup', 'minutes': reminder_minutes}],
        }
    return body


@app.post('/calendar/sync', tags=['Syllabus to Calendar'])
@limiter.limit("20/minute")
async def sync_class_calendar(request: Request, email: str = Query(...), body: CalendarClassSyncRequest = Body(...)):
    """
    Idempotent sync of a class's events to a dedicated secondary Google Calendar.

    - Creates the secondary calendar if it doesn't exist yet (find-or-create by name).
    - Patches events that already have a google_event_id (patch, not update, so
      anything the user added to the event directly in Google Calendar — location,
      attendees, notes — survives a re-sync). A patch that 404s (event deleted in
      Google, or a stale id) recreates just that event.
    - Inserts new events that have no google_event_id.
    - Deletes events marked is_deleted=True (if they have a google_event_id).
    - Falls back to a full rebuild only if incremental sync fails outright.

    Returns the google_calendar_id and per-event mappings {local_id, google_event_id}.
    """
    try:
        creds_data = get_google_credentials(email)
        if not creds_data:
            return JSONResponse(status_code=401, content={"error": "User not authenticated."})

        service = build('calendar', 'v3', credentials=_build_credentials(creds_data))

        # ── Step 1: get or create the secondary calendar ──────────────────────
        cal_id = None
        if body.google_calendar_id:
            try:
                service.calendars().get(calendarId=body.google_calendar_id).execute()
                cal_id = body.google_calendar_id
                # Update colors for existing calendar if provided
                if body.background_color or body.foreground_color:
                    _set_calendar_colors(service, cal_id, body.background_color, body.foreground_color)
            except Exception:
                # Calendar was deleted externally — fall through to find-or-create
                pass
        if not cal_id:
            cal_id = _find_or_create_calendar(service, body.class_name, body.background_color, body.foreground_color)

        # ── Step 2: incremental sync ──────────────────────────────────────────
        synced_events = []
        try:
            for event in body.events:
                if event.is_deleted:
                    if event.google_event_id:
                        try:
                            service.events().delete(
                                calendarId=cal_id, eventId=event.google_event_id
                            ).execute()
                        except Exception:
                            pass  # already deleted — that's fine
                    # deleted events are not returned in synced_events
                elif event.google_event_id:
                    # Patch the existing event — only the fields we send are
                    # touched, so the user's own additions in Google Calendar are
                    # kept. If the event is gone (404/410), recreate just this one.
                    event_body = _build_google_event_body(event, body.reminder_minutes)
                    try:
                        result = service.events().patch(
                            calendarId=cal_id,
                            eventId=event.google_event_id,
                            body=event_body
                        ).execute()
                    except HttpError as patch_err:
                        if patch_err.resp.status in (404, 410):
                            result = service.events().insert(
                                calendarId=cal_id, body=event_body
                            ).execute()
                        else:
                            raise
                    synced_events.append({"local_id": event.local_id, "google_event_id": result['id']})
                else:
                    # Insert new event
                    created = service.events().insert(
                        calendarId=cal_id,
                        body=_build_google_event_body(event, body.reminder_minutes)
                    ).execute()
                    synced_events.append({"local_id": event.local_id, "google_event_id": created['id']})

        except RefreshError:
            raise  # dead token — no point attempting a full rebuild; handled below
        except Exception as incremental_err:
            # ── Fallback: rebuild the entire calendar ─────────────────────────
            logger.warning("Incremental sync failed (%s); falling back to full rebuild",
                           incremental_err)
            # Delete all events in the calendar
            page_token = None
            while True:
                events_result = service.events().list(
                    calendarId=cal_id, pageToken=page_token
                ).execute()
                for ev in events_result.get('items', []):
                    try:
                        service.events().delete(calendarId=cal_id, eventId=ev['id']).execute()
                    except Exception:
                        pass
                page_token = events_result.get('nextPageToken')
                if not page_token:
                    break

            synced_events = []
            for event in body.events:
                if event.is_deleted:
                    continue
                created = service.events().insert(
                    calendarId=cal_id,
                    body=_build_google_event_body(event, body.reminder_minutes)
                ).execute()
                synced_events.append({"local_id": event.local_id, "google_event_id": created['id']})

        return JSONResponse(status_code=200, content={
            "google_calendar_id": cal_id,
            "synced_events": synced_events
        })

    except RefreshError:
        return JSONResponse(status_code=401, content={
            "error": "Google access was revoked or expired. Please sign in again."
        })
    except Exception as e:
        logger.exception("Calendar sync failed")
        return JSONResponse(status_code=400, content={"error": f"Sync failed: {str(e)}"})


@app.delete('/calendar', tags=['Syllabus to Calendar'])
@limiter.limit("10/minute")
async def delete_class_calendar(request: Request, email: str = Query(...), google_calendar_id: str = Query(...)):
    """Delete a secondary Google Calendar by its ID."""
    try:
        creds_data = get_google_credentials(email)
        if not creds_data:
            return JSONResponse(status_code=401, content={"error": "User not authenticated."})

        service = build('calendar', 'v3', credentials=_build_credentials(creds_data))
        service.calendars().delete(calendarId=google_calendar_id).execute()
        return JSONResponse(status_code=200, content={"message": "Calendar deleted."})

    except RefreshError:
        return JSONResponse(status_code=401, content={
            "error": "Google access was revoked or expired. Please sign in again."
        })
    except Exception as e:
        logger.exception("Calendar delete failed")
        return JSONResponse(status_code=400, content={"error": f"Failed to delete calendar: {str(e)}"})


@app.post('/export', tags=['Export'])
@limiter.limit("20/minute")
async def export_events(
    request: Request,
    format: str = Query(...),
    email: str = Query(None),  # accepted for backwards compatibility; not required
    body: CalendarSyncRequest = Body(...)
):
    """Export parsed syllabus events as a downloadable .ics or .csv file.

    No Google credentials are required — this only serializes the events in the
    request body, so it works for guest users too.
    """
    if format.lower() not in ['ics', 'csv']:
        return JSONResponse(
            status_code=400,
            content={"error": "format must be 'ics' or 'csv'"}
        )

    if not body.events:
        return JSONResponse(
            status_code=400,
            content={"error": "No events provided"}
        )

    try:
        if format.lower() == 'ics':
            return _build_ics_response(body.events)
        else:
            return _build_csv_response(body.events)
    except Exception as e:
        logger.exception("Export failed")
        return JSONResponse(
            status_code=400,
            content={"error": f"Failed to export events: {str(e)}"}
        )


def _build_ics_response(events: List[CalendarEvent]) -> StreamingResponse:
    """Build a valid RFC 5545 iCalendar response from the given events."""
    cal = ICalendar()
    cal.add('prodid', '-//Plannr//Syllabus Export//EN')
    cal.add('version', '2.0')
    for ev in events:
        vevent = ICalEvent()
        vevent.add('summary', ev.title)
        vevent.add('dtstart', date_type.fromisoformat(ev.date))
        vevent.add('dtend', date_type.fromisoformat(ev.date))
        if ev.description:
            vevent.add('description', ev.description)
        if ev.type:
            vevent.add('categories', [ev.type])
        cal.add_component(vevent)
    buf = io.BytesIO(cal.to_ical())
    return StreamingResponse(
        buf,
        media_type='text/calendar',
        headers={'Content-Disposition': 'attachment; filename="events.ics"'}
    )


def _build_csv_response(events: List[CalendarEvent]) -> StreamingResponse:
    """Build a CSV response with columns: Title, Date, Type, Description."""
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['Title', 'Date', 'Type', 'Description'])
    for ev in events:
        writer.writerow([ev.title, ev.date, ev.type or '', ev.description or ''])
    return StreamingResponse(
        io.BytesIO(output.getvalue().encode('utf-8')),
        media_type='text/csv',
        headers={'Content-Disposition': 'attachment; filename="events.csv"'}
    )


_CLOUDFLARE_BEACON = (
    "<script type='module' src='https://static.cloudflareinsights.com/beacon.min.js' "
    "data-cf-beacon='{\"token\": \"56b37c71bdaf4f969a3b2ad12a8bd943\"}'></script>"
)

_TESTFLIGHT_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>{title}</title>
{analytics}
<style>
  body {{
    margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
    background: #07111d; color: #f5f7fa; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    text-align: center; padding: 24px; box-sizing: border-box;
  }}
  .card {{ max-width: 420px; }}
  h1 {{ font-size: 1.5rem; margin-bottom: 12px; }}
  p {{ color: #9aa5b1; line-height: 1.6; margin-bottom: 28px; }}
  a.btn {{
    display: inline-block; padding: 13px 26px; border-radius: 10px; font-weight: 600;
    text-decoration: none; background: #4f8cff; color: #07111d;
  }}
</style>
</head>
<body>
  <div class="card">
    <h1>{heading}</h1>
    <p>{message}</p>
    {action}
  </div>
</body>
</html>"""


@app.get('/testflight/success', tags=['TestFlight'], response_class=HTMLResponse)
@limiter.limit("10/minute")
async def testflight_success(request: Request, session_id: str = Query(...)):
    """Verify a completed Stripe Checkout session and reveal the TestFlight link."""
    if not _stripe_client:
        return HTMLResponse(
            _TESTFLIGHT_PAGE.format(
                title="Not configured", heading="Not configured yet",
                message="Stripe isn't set up on this server. Email mattheweblanke@gmail.com for help.", action="", analytics=""
            ),
            status_code=500
        )

    try:
        session = _stripe_client.v1.checkout.sessions.retrieve(session_id)
    except Exception:
        return HTMLResponse(
            _TESTFLIGHT_PAGE.format(
                title="Invalid session", heading="We couldn't verify that",
                message="This link looks invalid or expired. If you were just charged, email mattheweblanke@gmail.com.", action="",
                analytics=""
            ),
            status_code=400
        )

    if session.payment_status != 'paid':
        return HTMLResponse(
            _TESTFLIGHT_PAGE.format(
                title="Payment incomplete", heading="Payment not completed",
                message="We couldn't confirm your payment. If you believe this is an error, email mattheweblanke@gmail.com.", action="",
                analytics=""
            ),
            status_code=402
        )

    if not settings.testflight_link:
        return HTMLResponse(
            _TESTFLIGHT_PAGE.format(
                title="Almost there", heading="Payment confirmed!",
                message="We're still finishing TestFlight setup — check back shortly, or email mattheweblanke@gmail.com for your access link.",
                action="", analytics=""
            ),
            status_code=200
        )

    return HTMLResponse(
        _TESTFLIGHT_PAGE.format(
            title="You're in", heading="You're in!",
            message="Thanks for your purchase. Tap below to join the Plannr TestFlight beta.",
            action=f'<a class="btn" href="{settings.testflight_link}">Join TestFlight</a>',
            analytics=_CLOUDFLARE_BEACON
        )
    )


@app.post('/stripe/webhook', tags=['TestFlight'])
@limiter.exempt
async def stripe_webhook(request: Request):
    """Source of truth for TestFlight access grants — the success page is UX only.

    Customers aren't guaranteed to land on the success page (e.g. they close the tab
    after paying), so fulfillment must be driven from this event handler, not the redirect.

    Exempt from IP rate limiting: Stripe sends webhook events from a shared pool of IPs
    across all its customers, so per-IP limits here could throttle unrelated Stripe
    traffic. The signature check above already rejects anything not actually from Stripe.
    """
    if not settings.stripe_webhook_secret:
        return JSONResponse(status_code=500, content={"error": "Webhook not configured"})

    payload = await request.body()
    sig_header = request.headers.get('stripe-signature', '')
    try:
        event = stripe.Webhook.construct_event(payload, sig_header, settings.stripe_webhook_secret)
    except (ValueError, stripe.SignatureVerificationError):
        return JSONResponse(status_code=400, content={"error": "Invalid signature"})

    event_type = event['type']
    session = event['data']['object'].to_dict()

    if event_type in ('checkout.session.completed', 'checkout.session.async_payment_succeeded'):
        if session.get('payment_status') != 'unpaid':
            email = (session.get('customer_details') or {}).get('email')
            logger.info("TestFlight payment confirmed (session=%s, email=%s)",
                        session.get('id'), _mask_email(email))
            # Extension point: email the TestFlight link here as a durability backstop
            # for customers who never land on /testflight/success.
    elif event_type == 'checkout.session.async_payment_failed':
        logger.info("TestFlight payment failed (session=%s)", session.get('id'))

    return JSONResponse(status_code=200, content={"received": True})
