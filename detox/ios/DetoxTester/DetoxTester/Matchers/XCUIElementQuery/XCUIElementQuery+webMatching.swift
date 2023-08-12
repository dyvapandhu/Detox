//
//  XCUIElementQuery+webMatching.swift (DetoxTesterApp)
//  Created by Asaf Korem (Wix.com) on 2023.
//

import Foundation
import DetoxInvokeHandler
import XCTest

/// Extension to `XCUIElementQuery` that adds matching capabilities that uses the white-box handler of Detox
/// (which are not available in XCUITest).
extension XCUIElementQuery {
  /// Returns a new query matches the given pattern.
  func webMatching(
    pattern: WebElementPattern,
    webView: XCUIElement,
    whiteBoxMessageHandler: WhiteBoxMessageHandler
  ) throws -> XCUIElementQuery {
    switch pattern {
      case .id, .className, .cssSelector, .name, .xpath, .href, .hrefContains, .tag:
        matcherLog("matching web-element with pattern: `\(pattern)`, using white-box JS operation")
        let elementsMatcher = try createJSElementsMatcher(pattern: pattern)

        // Create a JS code that uses the function generated above, and for each element replaces
        // its aria-label to a unique value and eventually return the list of new labels to match
        // natively.
        let script = """
          (() => {
            function estimateiOSLabel(element) {
              // If the element is an image, use the alt text.
              if (element.tagName === "IMG") {
                return element.getAttribute("alt") || "";
              }

              // If element has associated label via 'for' attribute, use it.
              if (element.tagName === "INPUT" || element.tagName === "TEXTAREA" ||
                  element.tagName === "SELECT") {
                const labelForThis = document.querySelector(`label[for="${element.id}"]`);
                if (labelForThis) {
                  return labelForThis.textContent.trim();
                }
              }

              // If it's a label element with a 'for' attribute, get the associated element's value.
              if (element.tagName === "LABEL" && element.getAttribute('for')) {
                const associatedElem = document.getElementById(element.getAttribute('for'));

                if (associatedElem && (associatedElem.tagName === "INPUT" ||
                    associatedElem.tagName === "TEXTAREA")) {
                  return associatedElem.value || element.textContent.trim();
                }
              }

              // If there's a title attribute, use it.
              if (element.getAttribute("title")) {
                return element.getAttribute("title");
              }

              // If none of the above, use the text content or value.
              return element.textContent.trim() || element.value || "";
            }

            let elements = \(elementsMatcher)();

            let labels = [];
            for (let i = 0; i < elements.length; i++) {
              let element = elements[i];

              let elementLabel = estimateiOSLabel(element);
              let hasEstimatedLabel = elementLabel && elementLabel.trim().length > 0;

              let elementAriaLabel = element.getAttribute("aria-label");
              let hasAriaLabel = elementAriaLabel && elementAriaLabel.trim().length > 0;

              if (!hasEstimatedLabel && !hasAriaLabel) {
                elementLabel = 'detox-autogenerated-' + i;
              } else if (hasEstimatedLabel && !hasAriaLabel) {
                elementLabel = elementLabel + '-detox-autogenerated-' + i;
              } else if (elementAriaLabel.indexOf(elementLabel + '-detox-autogenerated-') === -1) {
                elementLabel = elementLabel + '-detox-autogenerated-' + i;
              } else {
                // Otherwise, it already has aria-label with the expected form (autogenerated).
                elementLabel = elementAriaLabel;
              }

              element.setAttribute('aria-label', elementLabel);
              labels.push(elementLabel);
            }

            return labels.map((label) => label.toString()).join(',');
          })();
          """

        let response = whiteBoxMessageHandler(
          .evaluateJavaScript(webViewElement: webView, script: script)
        )

        guard let response = response else {
          matcherLog(
            "cannot match by this pattern (\(pattern)) type using the XCUITest framework`",
            type: .error
          )

          throw Error.operationNotSupported(pattern: pattern)
        }

        guard case .string(let string) = response else {
          matcherLog(
            "response for white-box is not strings: \(response), failed to match any element",
            type: .info
          )

          if case .failed(let reason) = response {
            matcherLog("got error: \(reason)", type: .error)
          }

          return matchingNone()
        }

        matcherLog("found elements with aria-labels: \(string)")

        let ariaLabelsFound = string.split(separator: ",").map { String($0) }
        return webViews.descendants(matching: .any).matching(NSPredicate { evaluatedObject, _ in
          guard let element = evaluatedObject as? NSObject else {
            return false
          }

          let label = element.value(forKey: "label") as? String

          guard let label = label else {
            return false
          }

          return ariaLabelsFound.contains(label)
        })


      case .label(let label):
        return webViews.descendants(matching: .any).matching(NSPredicate { evaluatedObject, _ in
          guard let element = evaluatedObject as? NSObject else {
            return false
          }

          let elementLabel = element.value(forKey: "label") as? String
          guard let elementLabel = elementLabel else {
            return false
          }

          let regexPattern = "^\(label)(-detox-autogenerated-\\d+)?$"
          if let regex = try? NSRegularExpression(pattern: regexPattern, options: []) {
            let range = NSRange(location: 0, length: elementLabel.utf16.count)
            return regex.firstMatch(in: elementLabel, options: [], range: range) != nil
          }

          return false
        })

      case .value(let value):
        return webViews.descendants(matching: .any).matching(NSPredicate { evaluatedObject, _ in
          guard let element = evaluatedObject as? NSObject else {
            return false
          }
          return element.value(forKey: "value") as? String == value
        })
    }
  }

  /// Returns a JS function for matching an element based on the given `pattern`.
  private func createJSElementsMatcher(pattern: WebElementPattern) throws -> String {
    switch pattern {
      case .id(let id):
        return "(() => Array.from(document.querySelectorAll('#\(id)')))"

      case .className(let className):
        return "(() => Array.from(document.getElementsByClassName('\(className)')))"

      case .cssSelector(let cssSelector):
        return "(() => Array.from(document.querySelectorAll('\(cssSelector)')))"

      case .name(let name):
        return "(() => Array.from(document.getElementsByName('\(name)')))"

      case .xpath(let xpath):
        let cleanXpath = xpath.replacingOccurrences(of: "'", with: "\\'")

        return """
          (() => {
            let iterator = document.evaluate('\(cleanXpath)', document, null, XPathResult.ORDERED_NODE_ITERATOR_TYPE, null);
            let result = [];
            let node = iterator.iterateNext();
            while (node) {
              result.push(node);
              node = iterator.iterateNext();
            }
            return result;
          })
          """

      case .href(let href):
        return "(() => Array.from(document.querySelectorAll('[href=\"\(href)\"]')))"

      case .hrefContains(let substring):
        return "(() => Array.from(document.querySelectorAll('[href*=\"\(substring)\"]')))"

      case .tag(let tag):
        return "(() => Array.from(document.getElementsByTagName('\(tag)')))"

      case .label, .value:
        throw Error.operationNotSupported(pattern: pattern)
    }
  }
}
