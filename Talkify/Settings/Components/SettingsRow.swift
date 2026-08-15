import SwiftUI

/// One preference row: title, optional description, trailing control.
struct SettingsRow<Control: View>: View {
  let title: String
  var description = ""
  @ViewBuilder let control: Control

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 13, weight: .medium))
        if !description.isEmpty {
          Text(description)
            .font(.caption)
            .foregroundStyle(.white.opacity(contrast == .increased ? 0.72 : 0.48))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 12)
      control
    }
    .padding(.vertical, 13)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(.white.opacity(contrast == .increased ? 0.16 : 0.07))
        .frame(height: 1)
    }
  }
}

/// A SettingsRow whose control is a slider over a continuous range, with the
/// current value read out beside it. For preferences with no natural set of
/// named choices, where a picker would only invent arbitrary steps.
struct SettingsSliderRow: View {
  let title: String
  var description = ""
  @Binding var value: Double
  let range: ClosedRange<Double>
  /// The slider still steps: a stored value the user cannot land on again
  /// makes the preference feel unrepeatable.
  var step: Double = 0.05
  let valueLabel: (Double) -> String
  var controlWidth: CGFloat = 150

  var body: some View {
    SettingsRow(title: title, description: description) {
      HStack(spacing: 10) {
        Slider(value: $value, in: range, step: step)
          .labelsHidden()
          .tint(SettingsTheme.accent)
        Text(valueLabel(value))
          .font(.system(size: 12, weight: .medium))
          .monospacedDigit()
          .foregroundStyle(.white.opacity(0.62))
          .frame(width: 36, alignment: .trailing)
      }
      .frame(width: controlWidth)
    }
  }
}

/// The repeated shape of most preference rows: a SettingsRow whose control
/// is the standard trailing menu picker.
struct SettingsPickerRow<Value: Hashable>: View {
  let title: String
  var description = ""
  let options: [Value]
  let optionLabel: (Value) -> String
  @Binding var selection: Value
  var controlWidth: CGFloat = 150

  var body: some View {
    SettingsRow(title: title, description: description) {
      Picker(title, selection: $selection) {
        ForEach(options, id: \.self) { option in
          Text(optionLabel(option)).tag(option)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(width: controlWidth, alignment: .trailing)
    }
  }
}
