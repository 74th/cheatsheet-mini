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
                replaceChildren(...nodes) {
                    this.children = nodes;
                    this.textContent = nodes.map(node => node.textContent).join('');
                },
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
        XCTAssertEqual(button.forProperty("className").toString(), "copy-code")
        context.evaluateScript("replaced.children[1].listeners.click()")
        XCTAssertNil(exception, exception?.toString() ?? "")
        XCTAssertEqual(context.evaluateScript("copied").toArray() as? [String], ["gh auth token | sbx secret set github"])
        XCTAssertEqual(button.forProperty("title").toString(), "コピーしました")
        XCTAssertEqual(button.forProperty("className").toString(), "copy-code copied")
    }

    func testEachLineIsWrappedInItsOwnSpan() throws {
        let context = try XCTUnwrap(JSContext())
        var exception: JSValue?
        context.exceptionHandler = { _, value in exception = value }
        context.evaluateScript("""
        var copied = [];
        function element(tag) {
            return { tag: tag, children: [], listeners: {}, textContent: '',
                addEventListener(type, listener) { this.listeners[type] = listener; },
                append(...nodes) { this.children.push(...nodes); },
                replaceChildren(...nodes) {
                    this.children = nodes;
                    this.textContent = nodes.map(node => node.textContent).join('');
                },
                replaceWith(node) { replaced = node; },
                querySelector(selector) { return selector === 'code' ? this.code : null; } };
        }
        var replaced = null;
        var pre = element('pre');
        pre.code = element('code');
        pre.code.textContent = 'first\\n\\n  third\\n';
        var document = { querySelectorAll: () => [pre], createElement: element };
        var window = { webkit: { messageHandlers: { copyCode: { postMessage: text => copied.push(text) } } } };
        function setTimeout() { return 0; }
        function clearTimeout() {}
        """)
        context.evaluateScript(codeCopyScript)
        XCTAssertNil(exception, exception?.toString() ?? "")
        XCTAssertEqual(
            context.evaluateScript("pre.code.children.map(line => line.className + ':' + line.textContent)").toArray() as? [String],
            ["code-line:first\n", "code-line:\n", "code-line:  third\n"]
        )
        context.evaluateScript("replaced.children[1].listeners.click()")
        XCTAssertEqual(context.evaluateScript("copied").toArray() as? [String], ["first\n\n  third"])
    }
}
