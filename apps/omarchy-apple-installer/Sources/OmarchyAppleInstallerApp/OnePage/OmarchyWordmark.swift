import SwiftUI

/// The omarchy.org pixel wordmark, drawn from its cell grid so it stays crisp
/// at any size, coloured with the cyan-to-purple gradient of the site's hero
/// art. No image file is involved.
struct OmarchyWordmark: View {
  /// 81 × 19 cells, sampled from the site's OpenGraph image.
  static let grid: [String] = [
    ".................###.............................................................",
    "..#####......###########......#######....#######....#######....#...#......#...#..",
    ".#######....#############....########...########...########...##...##....##...##.",
    "###...###..###...###...###..###...###..###...###..###...###..###...###..###...###",
    "###...###..###...###...###..###...###..###...###..###...###..###...###..###...###",
    "###...###..###...###...###..###...###..###...###..###...##...###...###..###...###",
    "###...###..###...###...###..###...###..###...###..###...#....###...###..###...###",
    "###...###..###...###...###..###...###..###...###..###........###...###..###...###",
    "###...###..###...###...###.##########.#########...###.......###########.#########",
    "###...###..###...###...###.##########.########....###......###########..#########",
    "###...###..###...###...###..###...###..###........###........###...###........###",
    "###...###..###...###...###..###...###.##########..###...#....###...###...##...###",
    "###...###..###...###...###..###...###.##########..###...##...###...###..###...###",
    "###...###..###...###...###..###...###..###...###..###...###..###...###..###...###",
    "###...###..###...###...###..###...###..###...###..###...###..###...###..###...###",
    ".#######....##...###...##...###...##...###...###..########...###...##....#######.",
    "..#####......#...###...#....###...#....###...###..#######....###...#......#####..",
    ".......................................###...##..................................",
    ".......................................###...#...................................",
  ]

  /// One colour per cell row, top to bottom: white, turquoise, cyan, blue,
  /// purple, magenta.
  static let rowColors: [Color] = [
    0xFF_FFFF, 0xEA_FDFF, 0xC8_FAFB, 0xB4_F9F8, 0x9D_EFF9, 0x86_DFFA, 0x7D_CFFF,
    0x67_C4F9, 0x55_B5F2, 0x47_A4EA, 0x3F_93E3, 0x4A_80D8, 0x56_70CB, 0x64_62BE,
    0x71_56B3, 0x7C_4CAB, 0x8A_45A8, 0x9C_3EA6, 0xA8_3AA3,
  ].map(rgb)

  static let columns = grid[0].count
  static let rows = grid.count

  var body: some View {
    Canvas { context, size in
      let columns = CGFloat(Self.columns)
      let rows = CGFloat(Self.rows)
      let cell = min(size.width / columns, size.height / rows)
      let originX = (size.width - cell * columns) / 2
      let originY = (size.height - cell * rows) / 2
      for (row, line) in Self.grid.enumerated() {
        let colour = Self.rowColors[row]
        for (column, character) in line.enumerated() where character == "#" {
          let rect = CGRect(
            x: originX + CGFloat(column) * cell,
            y: originY + CGFloat(row) * cell,
            width: cell + 0.4,
            height: cell + 0.4
          )
          context.fill(Path(rect), with: .color(colour))
        }
      }
    }
    .aspectRatio(CGFloat(Self.columns) / CGFloat(Self.rows), contentMode: .fit)
    .accessibilityLabel("Omarchy")
  }

  nonisolated private static func rgb(_ hex: Int) -> Color {
    Color(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}
