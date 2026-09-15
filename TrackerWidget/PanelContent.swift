import SwiftUI

// MARK: - View model: one payload per tracker, shared refresh cadence

@MainActor
final class PanelViewModel: ObservableObject {
  @Published var selectedTab: Tracker = .pig
  @Published var pig: PricesPayload?
  @Published var shrimp: PricesPayload?
  @Published var grains: PricesPayload?
  @Published var failed = false

  private var timer: Timer?
  private var fastRetry: Timer?

  init() {
    // Steady state: sources update 2x/day to monthly; 30 min refresh is
    // generous and keeps the panel cheap. Failure with no data: 60s retries.
    timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refreshAll() }
    }
  }

  var payloadForSelected: PricesPayload? {
    switch selectedTab {
    case .pig: return pig
    case .shrimp: return shrimp
    // Chemicals rides the grains backend — same payload, filtered client-side.
    case .grains, .chemicals: return grains
    }
  }

  var hasAnyData: Bool { pig != nil || shrimp != nil || grains != nil }

  func refreshAll() {
    fetch(.pig) { [weak self] p in self?.pig = p }
    fetch(.shrimp) { [weak self] p in self?.shrimp = p }
    fetch(.grains) { [weak self] p in self?.grains = p }
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
      guard let self else { return }
      self.failed = !self.hasAnyData
      if self.failed {
        self.fastRetry?.invalidate()
        self.fastRetry = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
          Task { @MainActor in self?.refreshAll() }
        }
      } else {
        self.fastRetry?.invalidate()
        self.fastRetry = nil
      }
    }
  }

  private func fetch(_ tracker: Tracker, set: @escaping (PricesPayload?) -> Void) {
    PricesLoader.fetch(tracker) { result in
      Task { @MainActor in
        switch result {
        case .success(let payload): set(payload)
        case .failure: set(nil)
        }
      }
    }
  }
}

// MARK: - Content: tab bar + master layout

struct PanelContent: View {
  @ObservedObject var viewModel: PanelViewModel

  var body: some View {
    let palette = paletteFor(viewModel.selectedTab)
    VStack(spacing: 0) {
      tabBar(palette: palette)
      ZStack {
        palette.background.ignoresSafeArea()
        if let payload = viewModel.payloadForSelected {
          MasterLayout(payload: payload, tracker: viewModel.selectedTab, palette: palette)
        } else if viewModel.failed {
          FailureView(palette: palette)
        } else {
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.corner)
        .stroke(palette.border, lineWidth: 1)
    )
  }

  private func paletteFor(_ tab: Tracker) -> Theme.Palette {
    switch tab {
    case .pig: return Theme.pig
    case .shrimp: return Theme.shrimp
    case .grains: return Theme.grains
    case .chemicals: return Theme.chemicals
    }
  }

  // MARK: Tab bar — SVG icons + name, active tab highlighted, same width slots

  private func tabBar(palette: Theme.Palette) -> some View {
    HStack(spacing: 0) {
      tabButton(.pig, icon: "tab_pig", label: "Pig", palette: palette)
      tabButton(.shrimp, icon: "tab_shrimp", label: "Shrimp", palette: palette)
      tabButton(.grains, icon: "tab_grains", label: "Grains", palette: palette)
      tabButton(.chemicals, icon: "tab_chemicals", label: "Chemicals", palette: palette)
    }
    .frame(height: 40)
    .background(palette.surface)
    .overlay(Rectangle().fill(palette.border).frame(height: 0.5), alignment: .bottom)
  }

  private func tabButton(_ tab: Tracker, icon: String, label: String,
                         palette: Theme.Palette) -> some View {
    let isActive = viewModel.selectedTab == tab
    return Button {
      viewModel.selectedTab = tab
    } label: {
      VStack(spacing: 3) {
        HStack(spacing: 4) {
          if let img = NSImage(named: icon) {
            Image(nsImage: img)
              .resizable()
              .renderingMode(.template)
              .frame(width: 14, height: 14)
              .foregroundStyle(isActive ? palette.text : palette.dim)
          }
          Text(label)
            .font(Theme.tabFont)
            .foregroundStyle(isActive ? palette.text : palette.dim)
        }
        Rectangle()
          .fill(isActive ? palette.accent : Color.clear)
          .frame(height: 2)
      }
      .frame(maxWidth: .infinity)
      .padding(.top, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(isActive ? palette.activeTabBg : palette.inactiveTabBg)
  }
}

// MARK: - Failure state

private struct FailureView: View {
  let palette: Theme.Palette

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "wifi.exclamationmark")
        .foregroundStyle(Theme.down)
      Text("trackers unreachable")
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(palette.dim)
      Text("retrying every 60s…")
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(palette.faint)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(palette.background)
  }
}

// MARK: - MASTER LAYOUT — identical structure for all three trackers.
// Only `sections` differs per tracker (what to group by and which rows show).

private struct MasterLayout: View {
  let payload: PricesPayload
  let tracker: Tracker
  let palette: Theme.Palette

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(sections, id: \.0) { title, rows in
            sectionHeader(title, count: rows.count)
            ForEach(rows) { row in
              MarketRow(market: row, spark: payload.spark?[String(row.marketId)],
                        palette: palette, tracker: tracker)
            }
          }
        }
      }
      footer
    }
    .background(palette.background)
  }

  // Header: tracker-specific title (with icon) + shared unit label.
  // Title zone 30% taller per user request.
  private var header: some View {
    HStack(spacing: 8) {
      if let img = NSImage(named: headerIcon) {
        Image(nsImage: img)
          .resizable()
          .renderingMode(.template)
          .frame(width: 18, height: 18)
          .foregroundStyle(palette.text)   // matches the tab font color
      }
      Text(headerTitle)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(palette.text)
      Spacer()
      Text(headerUnit)
        .font(Theme.sectionFont)
        .foregroundStyle(palette.dim)
    }
    .padding(.horizontal, 14)
    .padding(.top, 16)
    .padding(.bottom, 10)
  }

  private var headerIcon: String {
    switch tracker {
    case .pig: return "tab_pig"
    case .shrimp: return "tab_shrimp"
    case .grains: return "tab_grains"
    case .chemicals: return "tab_chemicals"
    }
  }

  private var headerTitle: String {
    switch tracker {
    case .pig: return "Pig Prices"
    case .shrimp: return "Shrimp Prices"
    case .grains: return "Grains FOB"
    case .chemicals: return "Chemicals FOB"
    }
  }

  private var headerUnit: String {
    switch tracker {
    case .pig: return "USD/kg"
    case .shrimp: return "USD/kg"
    case .grains, .chemicals: return "USD/MT · Brazil → ASEAN"
    }
  }

  // MARK: Sections — per-tracker grouping logic, same rendering after this

  private var sections: [(String, [Market])] {
    switch tracker {
    case .pig:
      // Region sections, FATTENING PIGS only (per-head piglets not comparable)
      let rows = payload.markets
        .filter { $0.category == "FATTENING PIGS" }
        .sorted { ($0.usdPerKg ?? 0) > ($1.usdPerKg ?? 0) }
      let grouped = Dictionary(grouping: rows, by: { $0.region })
      return ["Europe", "America", "Asia", "Africa"]
        .compactMap { r in grouped[r].map { (r, $0) } }

    case .shrimp:
      // Single section — 5 markets, sorted by price
      let rows = payload.markets.sorted { ($0.usdPerKg ?? 0) > ($1.usdPerKg ?? 0) }
      return rows.isEmpty ? [] : [("VANNAMEI 30 PCS/KG · FARM GATE", rows)]

    case .grains:
      // Product sections with icons, rows by destination
      let grainsCats = ["CORN", "SOYBEANS", "SOY MEAL", "SOY PROTEIN", "COTTONSEED MEAL"]
      let rows = payload.markets.filter { grainsCats.contains($0.category) }
      let grouped = Dictionary(grouping: rows, by: { $0.category })
      let icons: [String: String] = ["CORN": "prod_corn", "SOYBEANS": "prod_soybeans",
                                     "SOY MEAL": "prod_soymeal", "SOY PROTEIN": "prod_soy_protein",
                                     "COTTONSEED MEAL": "prod_cottonseed"]
      return grainsCats.compactMap { cat in
        guard let catRows = grouped[cat], !catRows.isEmpty else { return nil }
        let sorted = catRows.sorted { ($0.usdPerKg ?? 0) > ($1.usdPerKg ?? 0) }
        return ("\(icons[cat] ?? "prod_corn")|\(cat)", sorted)
      }

    case .chemicals:
      // Three chemicals, rows by destination
      let chemCats = ["PURE GLYCERIN", "CRUDE GLYCERIN", "LECITHINS"]
      let rows = payload.markets.filter { chemCats.contains($0.category) }
      let grouped = Dictionary(grouping: rows, by: { $0.category })
      let icons: [String: String] = ["PURE GLYCERIN": "prod_glycerin_refined",
                                     "CRUDE GLYCERIN": "prod_glycerin_crude",
                                     "LECITHINS": "prod_lecithin"]
      return chemCats.compactMap { cat in
        guard let catRows = grouped[cat], !catRows.isEmpty else { return nil }
        let sorted = catRows.sorted { ($0.usdPerKg ?? 0) > ($1.usdPerKg ?? 0) }
        return ("\(icons[cat] ?? "prod_lecithin")|\(cat)", sorted)
      }
    }
  }

  /// Section header renders "icon|Category" tuples: icon asset + label.
  /// Colored product icons (user-specified colors) render original;
  /// everything else tints with the palette.
  private func isColoredIcon(_ name: String) -> Bool {
    name.contains("glycerin")
  }

  private func sectionHeader(_ title: String, count: Int) -> some View {
    let parts = title.split(separator: "|", maxSplits: 1).map(String.init)
    let iconName = parts.count == 2 ? parts[0] : nil
    let label = parts.count == 2 ? parts[1] : title
    return HStack {
      if let iconName, let img = NSImage(named: iconName) {
        let icon = Image(nsImage: img)
          .resizable()
          .renderingMode(isColoredIcon(iconName) ? .original : .template)
          .frame(width: 12, height: 12)
        if isColoredIcon(iconName) {
          icon   // user's colors (brown / light yellow) render as authored
        } else {
          icon.foregroundStyle(palette.dim)   // matches the section label color
        }
      }
      Text(label)
        .font(Theme.sectionFont)
        .foregroundStyle(palette.dim)
      Spacer()
      Text("\(count)")
        .font(Theme.sectionFont)
        .foregroundStyle(palette.faint)
    }
    .padding(.horizontal, 14)
    .padding(.top, 10)
    .padding(.bottom, 3)
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 2) {
      Rectangle().fill(palette.border).frame(height: 0.5)
        .padding(.horizontal, 14)
      HStack(spacing: 0) {
        Text("updated \(payload.generatedAt.suffix(16)) UTC · \(payload.totalHistoryRows) history rows · \(cadence)")
          .font(Theme.obsFont)
          .foregroundStyle(palette.faint)
          .lineLimit(1)
        Spacer()
        actionButtons
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 6)
    }
    .background(palette.surface)
  }

  /// Two yellow square buttons in the lower-right corner of every tab:
  /// screenshot (widget-cropped PNG) + Excel export (.xls to Desktop).
  private var actionButtons: some View {
    HStack(spacing: 8) {
      Button {
        WidgetActions.screenshot()
      } label: {
        actionIcon("act_screenshot", help: "Save widget screenshot to Desktop")
      }
      .buttonStyle(.plain)

      Button {
        WidgetActions.exportXls(tracker: tracker, sections: exportSections)
      } label: {
        actionIcon("act_excel", help: "Export listings to .xls on Desktop")
      }
      .buttonStyle(.plain)
    }
  }

  private func actionIcon(_ name: String, help: String) -> some View {
    Group {
      if let img = NSImage(named: name) {
        Image(nsImage: img)
          .resizable()
          .renderingMode(.template)
          .frame(width: 13, height: 13)
      }
    }
    .frame(width: 24, height: 24)
    .background(
      RoundedRectangle(cornerRadius: 5)
        .fill(Color(red: 0.95, green: 0.75, blue: 0.10).opacity(0.16)) // yellow wash
    )
    .overlay(
      RoundedRectangle(cornerRadius: 5)
        .stroke(Color(red: 0.95, green: 0.75, blue: 0.10), lineWidth: 1.2) // yellow frame
    )
    .foregroundStyle(Color(red: 0.95, green: 0.75, blue: 0.10))            // yellow glyph
    .help(help)
  }

  /// The sections as currently rendered (stripped of icon prefix) for export.
  private var exportSections: [(String, [Market])] {
    sections.map { (title, rows) in
      let clean = title.split(separator: "|", maxSplits: 1).last.map(String.init) ?? title
      return (clean, rows)
    }
  }

  private var cadence: String {
    switch tracker {
    case .pig: return "2x/day source"
    case .shrimp: return "weekly source"
    case .grains, .chemicals: return "monthly source"
    }
  }
}

// MARK: - Row: flag+name | sparkline | price | change% | arrow

private struct MarketRow: View {
  let market: Market
  let spark: [Double]?
  let palette: Theme.Palette
  let tracker: Tracker

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      // Column 1: flag + name
      HStack(spacing: 6) {
        Text(Theme.flagEmoji(market.flag))
          .font(.system(size: 13))
        Text(market.country)
          .font(Theme.rowFont)
          .foregroundStyle(palette.text)
          .lineLimit(1)
      }
      .frame(width: 120, alignment: .leading)

      // Column 2: sparkline
      if let spark, spark.count >= 2 {
        Sparkline(values: Array(spark.suffix(12)))
          .stroke(lineColor, lineWidth: 1.2)
          .frame(width: 52, height: 16)
      } else {
        Color.clear.frame(width: 52, height: 16)
      }

      // Column 3: price (USD/MT on grains, USD/kg elsewhere)
      Text(priceText)
        .font(Theme.monoFont)
        .monospacedDigit()
        .foregroundStyle(priceColor)
        .frame(width: priceWidth, alignment: .trailing)

      // Column 4: change %
      Text(changeText)
        .font(Theme.obsFont)
        .monospacedDigit()
        .foregroundStyle(changeColor)
        .frame(width: 44, alignment: .trailing)

      // Direction arrow
      if market.wentDown {
        Image(systemName: "arrow.down.right")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(Theme.down.opacity(0.9))
      } else if market.wentUp {
        Image(systemName: "arrow.up.right")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(Theme.up.opacity(0.9))
      }
    }
    .padding(.horizontal, 14)
    .frame(height: 23)
    .help(helpText)
  }

  private var priceWidth: CGFloat {
    (tracker == .grains || tracker == .chemicals) ? 52 : 62
  }

  private var priceText: String {
    guard let usd = market.usdPerKg else { return "—" }
    // Grains + Chemicals tabs quote USD/MT (bulk/lot convention); API serves usd_per_kg.
    if tracker == .grains || tracker == .chemicals {
      return String(format: "%.1f", usd * 1000)
    }
    return String(format: "%.2f", usd)
  }

  private var priceColor: Color {
    if market.usdPerKg == nil { return palette.dim }
    if tracker == .pig && market.variationSuspect { return palette.dim }
    if market.wentDown { return Theme.down.opacity(0.95) }
    if market.wentUp { return Theme.up.opacity(0.95) }
    return palette.text
  }

  private var lineColor: Color {
    if market.wentDown { return Theme.down.opacity(0.85) }
    if market.wentUp { return Theme.up.opacity(0.85) }
    return palette.dim
  }

  private var changeText: String {
    guard let v = market.variationPercent else { return "" }
    if tracker == .pig && market.variationSuspect { return "⚠︎" }
    return String(format: "%+.1f%%", v)
  }

  private var changeColor: Color {
    if market.wentDown { return Theme.down.opacity(0.8) }
    if market.wentUp { return Theme.up.opacity(0.8) }
    return palette.dim
  }

  private var helpText: String {
    var lines = [
      "\(market.country) — \(market.reference)",
      "\(market.priceDate)",
    ]
    if let usd = market.usdPerKg {
      lines.append((tracker == .grains || tracker == .chemicals)
        ? "USD/MT: \(String(format: "%.1f", usd * 1000)) · USD/kg: \(String(format: "%.4f", usd))"
        : "USD/kg: \(String(format: "%.3f", usd))")
    }
    if let v = market.variationPercent, !(tracker == .pig && market.variationSuspect) {
      lines.append("change: \(String(format: "%+.1f", v))%")
    }
    if tracker == .pig && market.variationSuspect {
      lines.append("pig333 variation data suspect this week")
    }
    return lines.joined(separator: "\n")
  }
}

// MARK: - Sparkline

private struct Sparkline: Shape {
  let values: [Double]

  func path(in rect: CGRect) -> Path {
    var path = Path()
    guard values.count >= 2,
          let vmin = values.min(), let vmax = values.max() else { return path }
    let range = max(vmax - vmin, 0.001)
    let stepX = rect.width / CGFloat(values.count - 1)
    for (i, v) in values.enumerated() {
      let x = CGFloat(i) * stepX
      let y = rect.height - CGFloat((v - vmin) / range) * rect.height
      if i == 0 {
        path.move(to: CGPoint(x: x, y: y))
      } else {
        path.addLine(to: CGPoint(x: x, y: y))
      }
    }
    return path
  }
}