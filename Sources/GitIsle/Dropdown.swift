import SwiftUI

/// A dropdown drawn inside the island, in place of a native menu: native menus open outside
/// the island, in the system's own style, and take the pointer from it. The expanded island
/// draws the open one over its content, so a control inside a scroll view isn't clipped.
struct Dropdown {
  struct Item: Identifiable {
    let id: String
    var title: String
    var systemImage: String?
    /// One of the app's own glyphs, in place of a system image.
    var glyph: Glyph?
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
  /// It fits its rows, up to this width; longer titles are cut in the middle.
  var maxWidth: CGFloat
  /// Lines the dropdown up with the control's trailing edge, for controls on the right.
  var trailing: Bool

  /// The expanded island's coordinate space, where anchors are measured.
  static let space = "dropdown"
  static let padding: CGFloat = 6
  static let headerHeight: CGFloat = 24
  static let dividerHeight: CGFloat = 9
  static let margin: CGFloat = 8

  /// Whether rows keep room for a checkmark: only when one shows a choice.
  var checkable: Bool { sections.contains { $0.items.contains(where: \.selected) } }

  var placement: Placement { Placement(anchor: anchor, trailing: trailing) }

  /// Where a dropdown opens in the island, from its control and its own size.
  struct Placement: Sendable {
    let anchor: CGRect
    let trailing: Bool

    /// Lined up with its control, and always inside the island.
    func x(width: CGFloat, in size: CGSize) -> CGFloat {
      let x = trailing ? anchor.maxX - width : anchor.minX
      return min(max(x, Dropdown.margin), size.width - width - Dropdown.margin)
    }

    /// Under its control, or over it when there's no room below.
    func y(height: CGFloat, in size: CGSize) -> CGFloat {
      let below = anchor.maxY + 6
      let above = anchor.minY - 6 - height
      return below + height > size.height - Dropdown.margin && above >= Dropdown.margin
        ? above : below
    }
  }
}

/// A control that opens a dropdown inside the island; a second click closes it.
struct DropdownButton<Label: View>: View {
  let id: String
  var maxWidth: CGFloat = 260
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
    Dropdown(id: id, anchor: frame, sections: sections(), maxWidth: maxWidth, trailing: trailing)
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
            .frame(maxWidth: .infinity, minHeight: Dropdown.headerHeight, alignment: .bottomLeading)
        }
        ForEach(section.items) { item in
          PickerRow(selected: item.selected, checkable: dropdown.checkable) {
            if let glyph = item.glyph {
              GlyphView(glyph: glyph, size: 12).foregroundStyle(.white.opacity(0.6))
                .frame(width: 16)
            } else if let symbol = item.systemImage {
              Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6)).frame(width: 16)
            }
            Text(item.title).lineLimit(1).truncationMode(.middle)
              .frame(maxWidth: dropdown.maxWidth - 60, alignment: .leading)
          } action: {
            close()
            item.action()
          }
          // Every row as wide as the widest, so highlights and checkmarks line up.
          .frame(maxWidth: .infinity)
          .disabled(!item.enabled)
          .opacity(item.enabled ? 1 : 0.4)
        }
      }
    }
    .padding(Dropdown.padding)
    .fixedSize()
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.1)))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline)
    )
    .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    .accessibilityElement(children: .contain)
  }
}
