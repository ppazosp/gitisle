import SwiftUI

/// A dropdown drawn inside the island, in place of a native menu: native menus open outside
/// the island, in the system's own style, and take the pointer from it. The expanded island
/// draws the open one over its content, so a control inside a scroll view isn't clipped.
struct Dropdown {
  struct Item: Identifiable {
    let id: String
    var title: String
    var systemImage: String?
    var selected = false
    var enabled = true
    let action: () -> Void
  }

  struct Section: Identifiable {
    let id: String
    var title: String?
    var items: [Item]
  }

  /// The control that opened it; the same control closes it again.
  let id: String
  /// The control's frame in the expanded island.
  let anchor: CGRect
  var sections: [Section]
  var width: CGFloat
  /// Lines the dropdown up with the control's trailing edge, for controls on the right.
  var trailing: Bool

  /// The expanded island's coordinate space, where anchors are measured.
  static let space = "dropdown"
  static let padding: CGFloat = 6
  static let headerHeight: CGFloat = 24
  static let dividerHeight: CGFloat = 9

  @MainActor var height: CGFloat {
    let rows = sections.reduce(0) { total, section in
      total + (section.title == nil ? 0 : Self.headerHeight)
        + CGFloat(section.items.count) * RepositoryPicker.rowHeight
    }
    return Self.padding * 2 + rows + CGFloat(max(sections.count - 1, 0)) * Self.dividerHeight
  }

  /// Where it opens in an island of this size: under the control, or over it when there's no
  /// room below, and always inside the island.
  @MainActor func origin(in size: CGSize) -> CGPoint {
    let margin: CGFloat = 8
    let x = trailing ? anchor.maxX - width : anchor.minX
    let below = anchor.maxY + 6
    let above = anchor.minY - 6 - height
    let y = below + height > size.height - margin && above >= margin ? above : below
    return CGPoint(x: min(max(x, margin), size.width - width - margin), y: y)
  }
}

/// A control that opens a dropdown inside the island; a second click closes it.
struct DropdownButton<Label: View>: View {
  let id: String
  var width: CGFloat = 200
  var trailing = false
  let sections: () -> [Dropdown.Section]
  @ViewBuilder let label: Label
  @Environment(IslandStore.self) private var store
  @State private var frame: CGRect = .zero

  var body: some View {
    Button {
      withAnimation(Motion.snappy) { store.dropdown = store.dropdown?.id == id ? nil : open() }
    } label: {
      label
    }
    .buttonStyle(.plain)
    .onGeometryChange(for: CGRect.self) {
      $0.frame(in: .named(Dropdown.space))
    } action: {
      frame = $0
      if store.pendingDropdown == id {
        store.pendingDropdown = nil
        store.dropdown = open()
      }
    }
  }

  private func open() -> Dropdown {
    Dropdown(id: id, anchor: frame, sections: sections(), width: width, trailing: trailing)
  }
}

/// The open dropdown: rows like the repository picker's, in sections.
struct DropdownMenu: View {
  let dropdown: Dropdown
  let close: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(dropdown.sections.enumerated()), id: \.element.id) { index, section in
        if index > 0 {
          Rectangle().fill(Palette.hairline).frame(height: 1)
            .padding(.vertical, (Dropdown.dividerHeight - 1) / 2)
        }
        if let title = section.title {
          Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 8)
            .frame(height: Dropdown.headerHeight, alignment: .bottomLeading)
        }
        ForEach(section.items) { item in
          PickerRow(selected: item.selected) {
            if let symbol = item.systemImage {
              Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6)).frame(width: 16)
            }
            Text(item.title).lineLimit(1).truncationMode(.middle)
          } action: {
            close()
            item.action()
          }
          .disabled(!item.enabled)
          .opacity(item.enabled ? 1 : 0.4)
        }
      }
    }
    .padding(Dropdown.padding)
    .frame(width: dropdown.width, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.1)))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline)
    )
    .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    .accessibilityElement(children: .contain)
  }
}
