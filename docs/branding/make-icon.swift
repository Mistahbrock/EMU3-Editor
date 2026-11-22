import AppKit
func render(_ px: Int, _ path: String) {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let s = CGFloat(px)
  let inset = s * 0.055, body = NSRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
  let sq = NSBezierPath(roundedRect: body, xRadius: s*0.17, yRadius: s*0.17)
  NSGradient(colors: [NSColor(white: 0.17, alpha: 1), NSColor(white: 0.06, alpha: 1)])!.draw(in: sq, angle: -90)
  NSColor(white: 1, alpha: 0.10).setStroke(); sq.lineWidth = s*0.006; sq.stroke()
  let blue = NSColor(calibratedRed: 0.0, green: 0.42, blue: 0.95, alpha: 1)
  let red = NSColor(calibratedRed: 0.90, green: 0.06, blue: 0.10, alpha: 1)
  // custom badge lettering, in units of the mark width W
  let W = s*0.62, h = W*0.31, t = W*0.07
  let wE = 0.19, wH = 0.095, wM = 0.31, wU = 0.215
  let gap = (1.0 - (wE + wH + wM + wU)) / 3.0
  let bh = s*0.098, bgap = s*0.043, textGap = s*0.055
  let total = h + textGap + 3*bh + 2*bgap
  let y0 = (s - total)/2, x0 = (s - W)/2
  for i in 0..<3 {
    let y = y0 + CGFloat(i)*(bh+bgap)
    red.setFill(); NSBezierPath(roundedRect: NSRect(x: x0, y: y, width: W, height: bh), xRadius: bh*0.06, yRadius: bh*0.06).fill()
  }
  let top = y0 + 3*bh + 2*bgap + textGap + h, bot = top - h
  blue.setFill()
  func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ hh: CGFloat) { NSBezierPath(rect: NSRect(x: x, y: y, width: w, height: hh)).fill() }
  var x = x0
  // E
  let eW = wE*W; R(x, bot, t, h); R(x, top - t*0.9, eW, t*0.9); R(x, bot + (h - t*0.9)/2, eW*0.86, t*0.9); R(x, bot, eW, t*0.9)
  x += (wE + gap)*W
  // hyphen
  R(x, bot + (h - t*0.9)/2, wH*W, t*0.9)
  x += (wH + gap)*W
  // M
  let mW = wM*W
  R(x, bot, t, h); R(x + mW - t, bot, t, h)
  let mid = bot + h*0.28
  for (ax, bx) in [(x, x + mW/2 - t*0.1), (x + mW, x + mW/2 + t*0.1)] {
    let p = NSBezierPath(); let dir: CGFloat = ax < bx ? 1 : -1
    p.move(to: NSPoint(x: ax, y: top)); p.line(to: NSPoint(x: ax + dir*t*1.15, y: top))
    p.line(to: NSPoint(x: bx + dir*t*0.0 + (dir > 0 ? t*0.55 : -t*0.55), y: mid)); p.line(to: NSPoint(x: bx - (dir > 0 ? t*0.55 : -t*0.55), y: mid)); p.close(); p.fill()
  }
  x += (wM + gap)*W
  // U
  let uW = wU*W
  let u = NSBezierPath(); let r = t*1.1
  u.move(to: NSPoint(x: x, y: top)); u.line(to: NSPoint(x: x, y: bot + r))
  u.curve(to: NSPoint(x: x + r, y: bot), controlPoint1: NSPoint(x: x, y: bot + r*0.3), controlPoint2: NSPoint(x: x + r*0.3, y: bot))
  u.line(to: NSPoint(x: x + uW - r, y: bot))
  u.curve(to: NSPoint(x: x + uW, y: bot + r), controlPoint1: NSPoint(x: x + uW - r*0.3, y: bot), controlPoint2: NSPoint(x: x + uW, y: bot + r*0.3))
  u.line(to: NSPoint(x: x + uW, y: top)); u.line(to: NSPoint(x: x + uW - t, y: top))
  u.line(to: NSPoint(x: x + uW - t, y: bot + t)); u.line(to: NSPoint(x: x + t, y: bot + t)); u.line(to: NSPoint(x: x + t, y: top)); u.close(); u.fill()
  NSGraphicsContext.restoreGraphicsState()
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
let d = CommandLine.arguments[1]
for (n, px) in [("16",16),("16@2x",32),("32",32),("32@2x",64),("128",128),("128@2x",256),("256",256),("256@2x",512),("512",512),("512@2x",1024)] { render(px, "\(d)/icon_\(n.replacingOccurrences(of:"@2x", with:"")).png".replacingOccurrences(of: n.contains("@") ? "icon_\(n.replacingOccurrences(of:"@2x", with:""))" : "x?x", with: n.contains("@") ? "icon_\(n.replacingOccurrences(of:"@2x", with:""))x\(n.replacingOccurrences(of:"@2x", with:""))@2x" : "icon_\(n)x\(n)")) }
