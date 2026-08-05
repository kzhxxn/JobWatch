import AppKit
import Foundation

let W: CGFloat = 1024
let cx: CGFloat = W / 2, cy: CGFloat = W / 2
let R: CGFloat = 300

func P(_ ang: Double, _ rad: CGFloat) -> NSPoint {
    NSPoint(x: cx + rad * CGFloat(cos(ang)), y: cy + rad * CGFloat(sin(ang)))
}

let img = NSImage(size: NSSize(width: W, height: W))
img.lockFocus()

// 배경: 다크 네이비 라운드 스퀘어
let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: W, height: W), xRadius: 190, yRadius: 190)
NSColor(srgbRed: 0.05, green: 0.07, blue: 0.14, alpha: 1).setFill()
bg.fill()

// 궤도(전체) — 은은한 선
let orbit = NSBezierPath(ovalIn: NSRect(x: cx - R, y: cy - R, width: 2 * R, height: 2 * R))
orbit.lineWidth = 20
NSColor(white: 1, alpha: 0.20).setStroke()
orbit.stroke()

// 발사 궤적(강조 호) — 70°→210° CCW
let accent = NSColor(srgbRed: 1.0, green: 0.55, blue: 0.2, alpha: 1)
let arc = NSBezierPath()
arc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: R, startAngle: 70, endAngle: 210)
arc.lineWidth = 30
arc.lineCapStyle = .round
accent.setStroke()
arc.stroke()

// 화살촉(호 끝, 접선 방향) — 돌아오는 방향
let endA = 210.0 * .pi / 180
let e = P(endA, R)
let tx = CGFloat(-sin(endA)), ty = CGFloat(cos(endA))   // 접선(CCW)
let px = -ty, py = tx                                    // 수직
let ah: CGFloat = 62
let head = NSBezierPath()
head.move(to: NSPoint(x: e.x + tx * ah, y: e.y + ty * ah))
head.line(to: NSPoint(x: e.x - tx * ah * 0.2 + px * ah * 0.62, y: e.y - ty * ah * 0.2 + py * ah * 0.62))
head.line(to: NSPoint(x: e.x - tx * ah * 0.2 - px * ah * 0.62, y: e.y - ty * ah * 0.2 - py * ah * 0.62))
head.close()
accent.setFill()
head.fill()

// 발사선(홈 → 궤도 시작점, "쏘는" 느낌)
let startA = 70.0 * .pi / 180
let spark = NSBezierPath()
spark.move(to: P(startA, 66))
spark.line(to: P(startA, R - 34))
spark.lineWidth = 14
spark.lineCapStyle = .round
NSColor(white: 1, alpha: 0.5).setStroke()
spark.stroke()

// 홈(중심 노드)
NSColor(white: 1, alpha: 0.95).setFill()
let dot: CGFloat = 46
NSBezierPath(ovalIn: NSRect(x: cx - dot, y: cy - dot, width: 2 * dot, height: 2 * dot)).fill()

img.unlockFocus()

let tiff = img.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "/Users/mark/DevGit/side/JobWatch/assets/appicon-geo.png"))
print("saved appicon-geo.png")
