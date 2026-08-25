# Privacy Policy for Plannr

*Last updated: August 25, 2026*

## 1. Introduction

Plannr ("we," "our," or "the App") is a student productivity tool that extracts key dates from course syllabi and syncs them to your Google Calendar. This privacy policy explains what data we collect, how we use it, and how you can request deletion.

## 2. Data We Collect

When you use Plannr, we collect and process the following:

- **Google Account Information:** Your name and email address, obtained through Google Sign-In.
- **Google OAuth Credentials:** Access and refresh tokens that allow Plannr to interact with your Google Calendar on your behalf.
- **Syllabus Documents:** PDF files you upload for parsing. These are processed to extract assignment due dates, exam dates, quiz dates, and other course deadlines.
- **Calendar Events:** The parsed event data (titles, dates, descriptions, and event types) generated from your syllabi.

## 3. How We Use Your Data

Google user data obtained through Plannr is used only to provide and improve Plannr's user-facing functionality, including authentication and Google Calendar synchronization, as described below:

- **Authentication:** Your Google account information is used to identify you and maintain your session.
- **Syllabus Parsing:** Uploaded PDF content is sent to Google's Gemini API solely to extract structured calendar event data (assignment, exam, and quiz dates). We do not retain the raw PDF content after processing. Your Google Calendar data and Google OAuth credentials are never sent to the Gemini API.
- **Calendar Syncing:** Your OAuth credentials are used to create events in your Google Calendar on your behalf. Events are added as all-day entries to your primary calendar.
- **Account Management:** Your email address serves as your unique account identifier in our system.

## 4. Third-Party Services

Plannr relies on the following Google services to function:

- **Google OAuth 2.0** — for authentication
- **Google Calendar API** — for creating calendar events
- **Google Gemini API** — for analyzing syllabus content and extracting dates

Your data is handled in accordance with [Google's Privacy Policy](https://policies.google.com/privacy). Plannr does not sell Google user data. We do not share, transfer, or disclose your data to any third party except as necessary to provide the functionality described in this policy.

## 5. Data Storage

- Account information and OAuth credentials are stored on our backend server in a local database.
- The iOS app stores only your name and email locally on your device.
- We do not use analytics services or third-party tracking tools.

## 6. Data Protection & Security

We take the following measures to protect your data, including sensitive data such as your Google OAuth credentials:

- **Encryption in Transit:** All communication between the Plannr app, our backend server, and Google's APIs (OAuth, Calendar, Gemini) is encrypted using HTTPS/TLS.
- **Encryption at Rest:** Our database is hosted on Render, which encrypts data at rest at the infrastructure level.
- **Access Controls:** Our database is not publicly accessible and can only be reached by our backend service. OAuth access and refresh tokens are used exclusively server-side to make authorized calls to the Google Calendar API on your behalf and are never exposed in the app itself or in application logs.
- **Data Minimization:** We collect and retain only the data necessary to provide the syllabus-to-calendar service, as described in Section 2. We do not use analytics or third-party tracking tools.

## 7. Data Retention

Account information, Google OAuth credentials, and Plannr-generated calendar event metadata are retained while your account exists or until you request deletion (see Section 8). Uploaded syllabus content is not persistently stored after processing.

## 8. Requesting Data Deletion

You may request complete deletion of your account and all associated data at any time by contacting us at **plannr.ucsb@gmail.com**. Upon receiving your request, we will:

- Delete your account record and stored OAuth credentials from our database
- Remove any calendar or syllabus data associated with your account

Please note that events already synced to your Google Calendar will remain in your calendar unless you delete them manually, as they belong to your Google account.

## 9. Revoking Access

You can revoke Plannr's access to your Google account at any time by visiting your [Google Account Permissions](https://myaccount.google.com/permissions) page and removing Plannr.

## 10. Children's Privacy

Plannr is intended for university students and is not directed at children under 13. We do not knowingly collect data from children under 13.

## 11. Limited Use Compliance Statement

Plannr's use and transfer to any other app of information received from Google APIs will adhere to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements. Plannr does not use information obtained from Google Workspace APIs to develop, improve, or train generalized or non-personalized artificial intelligence or machine learning models.

## 12. Changes to This Policy

We may update this privacy policy from time to time. Any changes will be reflected by the "Last updated" date at the top of this page.
