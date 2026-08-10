//
//  TalkifyTests.swift
//  TalkifyTests
//
//  Created by Tornike Gomareli on 05/08/2026.
//

import Foundation
import Testing

struct TalkifyTests {
  @Test func hostIsTalkify() {
    #expect(Bundle.main.bundleIdentifier == "com.tgomareli.Talkify")
  }
}
