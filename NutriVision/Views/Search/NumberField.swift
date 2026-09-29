//
//  NumberField.swift
//  NutriVision
//

import SwiftUI

/// Labelled decimal input used by the manual-entry and profile forms.
struct NumberField: View {
    let title: String
    @Binding var value: Double
    var unit: String = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            if !unit.isEmpty {
                Text(unit).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
