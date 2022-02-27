//
//  ExpectationDelegate.swift (DetoxTester)
//  Created by Asaf Korem (Wix.com) on 2022.
//

import Foundation
import DetoxMessageHandler
import XCTest

class ExpectationDelegate: ExpectationDelegateProtocol {
  func expect(_ expectation: Expectation, isTruthy: Bool, on element: AnyHashable, timeout: Double?) throws {
    guard let element = element as? XCUIElement else {
      throw ExpectationDelegateError.notXCUIElement
    }

    switch expectation {
      case .toBeVisible(let threshold):
        XCTAssertEqual(element.isHittable, isTruthy)

      case .toBeFocused:
        XCTAssertEqual(element.accessibilityElementIsFocused(), isTruthy)

      case .toHaveText(let text):
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        XCTAssertEqual(element.staticTexts.containing(predicate).count > 0, isTruthy)

      case .toHaveId(let id):
        XCTAssertEqual(element.identifier == id, isTruthy)

      case .toHaveSliderInPosition(let normalizedPosition, let tolerance):
        XCTAssertLessThanOrEqual(element.normalizedSliderPosition, normalizedPosition + (tolerance ?? 0))
        XCTAssertGreaterThanOrEqual(element.normalizedSliderPosition, normalizedPosition - (tolerance ?? 0))

      case .toExist:
        XCTAssertEqual(element.exists, isTruthy)
    }
  }
}

extension ExpectationDelegate {
  enum ExpectationDelegateError: Error {
    case notXCUIElement
  }
}
