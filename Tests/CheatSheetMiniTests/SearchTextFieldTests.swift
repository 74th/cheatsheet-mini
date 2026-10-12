import XCTest
import AppKit
import SwiftUI
@testable import CheatSheetMini

private final class ComposingTextView: NSTextView {
    var composing = false
    override func hasMarkedText() -> Bool { composing }
}

final class SearchTextFieldTests: XCTestCase {
    @MainActor func testEditingCommandsRespectCompositionAndNativeEditing() {
        var actions: [String] = []
        let field = SearchTextField(text: .constant("検索"), focused: .constant(true),
                                    moveToResults: { actions.append("results") },
                                    submit: { actions.append("submit") },
                                    close: { actions.append("close") })
        let coordinator = field.makeCoordinator()
        let control = NSTextField()
        let editor = ComposingTextView()
        let down = #selector(NSResponder.moveDown(_:))
        let enter = #selector(NSResponder.insertNewline(_:))
        let escape = #selector(NSResponder.cancelOperation(_:))

        editor.composing = true
        for command in [down, enter, escape] {
            XCTAssertFalse(coordinator.control(control, textView: editor, doCommandBy: command))
        }
        XCTAssertTrue(actions.isEmpty, "IME commands must stay in the text editor")

        editor.composing = false
        XCTAssertFalse(coordinator.control(control, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        XCTAssertFalse(coordinator.control(control, textView: editor, doCommandBy: NSSelectorFromString("selectAll:")))
        XCTAssertTrue(actions.isEmpty, "Native selection and cursor movement must pass through")
        for command in [down, enter, escape] {
            XCTAssertTrue(coordinator.control(control, textView: editor, doCommandBy: command))
        }
        XCTAssertEqual(actions, ["results", "submit", "close"])
    }
}
