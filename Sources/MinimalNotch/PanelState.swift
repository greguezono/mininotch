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
