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
    case .grains: return grains
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
    }
  }

  // MARK: Tab bar — emoji + name, active tab highlighted, same width slots

  private func tabBar(palette: Theme.Palette) -> some View {
    HStack(spacing: 0) {
      tabButton(.pig, emoji: "🐷", label: "Pig", palette: palette)
      tabButton(.shrimp, emoji: "🦐", label: "Shrimp", palette: palette)
      tabButton(.grains, emoji: "🌾", label: "Grains", palette: palette)
    }
    .frame(height: 30)
    .background(palette.surface)
    .overlay(Rectangle().fill(palette.border).frame(height: 0.5), alignment: .bottom)
  }

  private func tabButton(_ tab: Tracker, emoji: String, label: String,
                         palette: Theme.Palette) -> some View {
    let isActive = viewModel.selectedTab == tab
    return Button {
      viewModel.selectedTab = tab
    } label: {
      VStack(spacing: 2) {
        Text("\(emoji) \(label)")
          .font(Theme.tabFont)
          .foregroundStyle(isActive ? palette.text : palette.dim)
        Rectangle()
          .fill(isActive ? palette.accent : Color.clear)
          .frame(height: 2)
      }
      .frame(maxWidth: .infinity)
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

  // Header: tracker-specific title + shared unit label
  private var header: some View {
    HStack(spacing: 6) {
      Text(headerTitle)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(palette.text)
      Spacer()
      Text(headerUnit)
        .font(Theme.sectionFont)
        .foregroundStyle(palette.dim)
    }
    .padding(.horizontal, 14)
    .padding(.top, 12)
    .padding(.bottom, 8)
  }

  private var headerTitle: String {
    switch tracker {
    case .pig: return "🐷 Pig Prices"
    case .shrimp: return "🦐 Shrimp Prices"
    case .grains: return "🌾 Grains FOB"
    }
  }

  private var headerUnit: String {
    tracker == .grains ? "USD/MT · Brazil → ASEAN" : "USD/kg"
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
      // Product sections with emoji, rows by destination
      let grouped = Dictionary(grouping: payload.markets, by: { $0.category })
      let emoji: [String: String] = ["CORN": "🌽", "SOYBEANS": "🫛",
                                     "SOY MEAL": "🌾", "SOY PROTEIN": "🛢️",
                                     "COTTONSEED MEAL": "☁️"]
      return ["CORN", "SOYBEANS", "SOY MEAL", "SOY PROTEIN", "COTTONSEED MEAL"]
        .compactMap { cat in
          guard let rows = grouped[cat], !rows.isEmpty else { return nil }
          let sorted = rows.sorted { ($0.usdPerKg ?? 0) > ($1.usdPerKg ?? 0) }
          return ("\(emoji[cat] ?? "•") \(cat)", sorted)
        }
    }
  }

  private func sectionHeader(_ title: String, count: Int) -> some View {
    HStack {
      Text(title)
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
      Text("updated \(payload.generatedAt.suffix(16)) UTC · \(payload.totalHistoryRows) history rows · \(cadence)")
        .font(Theme.obsFont)
        .foregroundStyle(palette.faint)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }
    .background(palette.surface)
  }

  private var cadence: String {
    switch tracker {
    case .pig: return "2x/day source"
    case .shrimp: return "weekly source"
    case .grains: return "monthly source"
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

  private var priceWidth: CGFloat { tracker == .grains ? 52 : 62 }

  private var priceText: String {
    guard let usd = market.usdPerKg else { return "—" }
    // Grains tab quotes USD/MT (bulk convention); API serves usd_per_kg.
    if tracker == .grains {
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
      lines.append(tracker == .grains
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