import AppKit

/// Panel actions: pixel-exact widget screenshot + .xls export, both saved
/// straight to the user's Desktop. Stdlib only.
enum WidgetActions {
  /// Set by PanelApp at launch — the panel whose content we capture/export.
  static weak var panel: NSPanel?

  private static func timestamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd-HHmmss"
    return f.string(from: Date())
  }

  // MARK: - Screenshot (renders OUR OWN view — no screen-recording permission)

  static func screenshot() {
    guard let view = panel?.contentView else {
      NSLog("[TrackerWidget] screenshot: no panel content view")
      return
    }
    view.needsDisplay = true
    view.displayIfNeeded()

    let bounds = view.bounds
    let scale = view.window?.backingScaleFactor ?? 2.0
    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: Int(bounds.width * scale),
      pixelsHigh: Int(bounds.height * scale),
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = bounds.size

    view.cacheDisplay(in: bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
      NSLog("[TrackerWidget] screenshot: PNG encode failed")
      return
    }

    let path = NSHomeDirectory() + "/Desktop/TrackerWidget-\(timestamp()).png"
    do {
      try png.write(to: URL(fileURLWithPath: path))
      NSLog("[TrackerWidget] screenshot saved: \(path)")
    } catch {
      NSLog("[TrackerWidget] screenshot write failed: \(error.localizedDescription)")
    }
  }

  // MARK: - Excel export (SpreadsheetML 2003, saved as .xls)

  static func exportXls(tracker: Tracker, sections: [(String, [Market])]) {
    let xml = spreadsheetML(tracker: tracker, sections: sections)
    let ext = tracker == .grains || tracker == .chemicals ? tracker.logTag : tracker.logTag
    let path = NSHomeDirectory() + "/Desktop/TrackerWidget-\(ext)-\(timestamp()).xls"
    do {
      try xml.data(using: .utf8)?.write(to: URL(fileURLWithPath: path))
      NSLog("[TrackerWidget] xls saved: \(path)")
    } catch {
      NSLog("[TrackerWidget] xls write failed: \(error.localizedDescription)")
    }
  }

  private static func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
     .replacingOccurrences(of: "\"", with: "&quot;")
  }

  private static func spreadsheetML(tracker: Tracker,
                                    sections: [(String, [Market])]) -> String {
    var rows: [String] = []

    // header style + title row
    rows.append("""
      <Row><Cell ss:StyleID="hdr"><Data ss:Type="String">Tracker</Data></Cell>\
      <Cell ss:StyleID="hdr"><Data ss:Type="String">Section</Data></Cell>\
      <Cell ss:StyleID="hdr"><Data ss:Type="String">Flag</Data></Cell>\
      <Cell ss:StyleID="hdr"><Data ss:Type="String">Country</Data></Cell>\
      <Cell ss:StyleID="hdr"><Data ss:Type="String">USD/kg</Data></Cell>\
      <Cell ss:StyleID="hdr"><Data ss:Type="String">USD/MT</Data></Cell>\
      <Cell ss:StyleID="hdr"><Data ss:Type="String">Period</Data></Cell>\
      <Cell ss:StyleID="hdr"><Data ss:Type="String">Change %</Data></Cell>\
      <Cell ss:StyleID="hdr"><Data ss:Type="String">Reference</Data></Cell></Row>
      """)

    let usdMT = tracker == .grains || tracker == .chemicals

    for (rawTitle, markets) in sections {
      // section titles carry an optional "icon|Label" encoding
      let title = rawTitle.split(separator: "|", maxSplits: 1).last.map(String.init) ?? rawTitle
      for m in markets {
        let usdKg = m.usdPerKg.map { String(format: "%.4f", $0) } ?? ""
        let mt = (usdMT && m.usdPerKg != nil) ? String(format: "%.1f", m.usdPerKg! * 1000) : ""
        var cells: [String] = []
        cells.append(cell("String", tracker.logTag))
        cells.append(cell("String", title))
        cells.append(cell("String", m.flag))
        cells.append(cell("String", m.country))
        cells.append(cell("String", usdKg))
        cells.append(cell("String", mt))
        cells.append(cell("String", m.priceDate))
        cells.append(cell("String", m.variation ?? ""))
        cells.append(cell("String", m.reference))
        rows.append("<Row>\(cells.joined())</Row>")
      }
    }

    let colWidths = (1...9).map { i in
      "<Column ss:Index=\"\(i)\" ss:AutoFitWidth=\"0\" ss:Width=\"\(i == 9 ? 220 : i == 4 ? 110 : 90)\"/>"
    }.joined()

    return """
      <?xml version="1.0"?>
      <?mso-application progid="Excel.Sheet"?>
      <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
       xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
       <Styles><Style ss:ID="hdr"><Font ss:Bold="1" ss:Color="#FFFFFF"/>\
      <Interior ss:Color="#1F2A44" ss:Pattern="Solid"/></Style></Styles>
       <Worksheet ss:Name="Tracker">
        <Table>\(colWidths)
      \(rows.joined(separator: "\n    "))
        </Table>
       </Worksheet>
      </Workbook>
      """
  }

  private static func cell(_ type: String, _ value: String) -> String {
    "<Cell><Data ss:Type=\"\(type)\">\(esc(value))</Data></Cell>"
  }
}