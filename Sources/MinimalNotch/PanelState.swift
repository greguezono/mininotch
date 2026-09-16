import Foundation

func pointerInsideActions(_ point: CGPoint, notch: CGRect?, panel: CGRect, panelVisible: Bool) -> Bool {
    func contains(_ rect: CGRect) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
    return notch.map(contains) == true || (panelVisible && contains(panel))
}

struct PanelState {
    private(set) var visible = false
    private var inside = false
    private var keyboard = false
    var hold = false
    mutating func enter() { inside = true; visible = true }
    mutating func exit() { inside = false }
    mutating func expire() { if !inside && !keyboard && !hold { visible = false } }
    mutating func showKeyboard() { keyboard = true; visible = true }
    mutating func escape() { keyboard = false; visible = false }
}
