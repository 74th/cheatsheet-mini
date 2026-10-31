import XCTest
import JavaScriptCore
@testable import CheatSheetMini

final class CodeCopyScriptTests: XCTestCase {
    // Run the injected script against a minimal DOM stand-in.
    func testButtonCopiesCodeWithoutFinalNewline() throws {
        let context = try XCTUnwrap(JSContext())
        var exception: JSValue?
        context.exceptionHandler = { _, value in exception = value }
        context.evaluateScript("""
        var copied = [];
        function element(tag) {
            return { tag: tag, children: [], listeners: {}, textContent: '',
                addEventListener(type, listener) { this.listeners[type] = listener; },
                append(...nodes) { this.children.push(...nodes); },
                replaceWith(node) { replaced = node; },
                querySelector(selector) { return selector === 'code' ? this.code : null; } };
        }
        var replaced = null;
        var pre = element('pre');
        pre.code = element('code');
        pre.code.textContent = 'gh auth token | sbx secret set github\\n';
        var document = { querySelectorAll: () => [pre], createElement: element };
        var window = { webkit: { messageHandlers: { copyCode: { postMessage: text => copied.push(text) } } } };
        function setTimeout() { return 0; }
        function clearTimeout() {}
        """)
        context.evaluateScript(codeCopyScript)
        XCTAssertNil(exception, exception?.toString() ?? "")
        let button = try XCTUnwrap(context.evaluateScript("replaced.children[1]"))
        XCTAssertEqual(button.forProperty("title").toString(), "コピー")
        XCTAssertTrue(button.forProperty("innerHTML").toString().hasPrefix("<svg"))
        context.evaluateScript("replaced.children[1].listeners.click()")
        XCTAssertNil(exception, exception?.toString() ?? "")
        XCTAssertEqual(context.evaluateScript("copied").toArray() as? [String], ["gh auth token | sbx secret set github"])
        XCTAssertEqual(button.forProperty("title").toString(), "コピーしました")
    }
}
