//
//  AddClassView.swift
//  Plannr
//
//  Created by Divya Subramonian on 2/12/26.
//

import SwiftUI

struct AddClassView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var classManager: ClassManager

    @State private var className: String = ""
    @State private var schedule = ClassSchedule()
    @State private var selectedColor: Color = .blue

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) {
                            Text("Add New Class")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            VStack(spacing: 20) {
                                // Class Name
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Class Name")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    TextField("e.g., Advanced Calculus", text: $className)
                                        .padding()
                                        .background(Color.gray.opacity(0.2))
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }

                                // Schedule (optional)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Schedule (Optional)")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    ClassSchedulePicker(schedule: $schedule)
                                }

                                // Color picker
                                HStack {
                                    Text("Class Color")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    ColorPicker("", selection: $selectedColor)
                                        .labelsHidden()
                                }
                            }
                            .padding(.horizontal)
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                    }

                    Button {
                        classManager.addClass(Class(
                            name: className,
                            schedule: schedule.displayString,
                            colorHex: selectedColor.toHex(),
                            structuredSchedule: schedule.isEmpty ? nil : schedule
                        ))
                        dismiss()
                    } label: {
                        Text("Add Class")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(className.isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(12)
                    }
                    .disabled(className.isEmpty)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

#Preview {
    AddClassView()
        .environmentObject(ClassManager())
}
