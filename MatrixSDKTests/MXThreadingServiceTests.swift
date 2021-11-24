// 
// Copyright 2021 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import XCTest

class MXThreadingServiceTests: XCTestCase {

    private var testData: MatrixSDKTestsData!
    
    override func setUp() {
        testData = MatrixSDKTestsData()
    }

    override func tearDown() {
        testData = nil
    }
    
    /// Test: Expect the threading service is initialized after creating a session
    /// - Create a Bob session
    /// - Expect threading service is initialized
    func testInitialization() {
        testData.doMXSessionTest(withBob: self) { bobSession, expectation in
            guard let bobSession = bobSession,
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                return
            }
            
            XCTAssertNotNil(bobSession.threadingService, "Threading service must be created")
            
            expectation.fulfill()
        }
    }
    
    /// Test: Expect a thread is created after sending an event to a thread
    /// - Create a Bob session
    /// - Create an initial room
    /// - Send a text message A to be used as thread root event
    /// - Send a threaded event B referencing the root event A
    /// - Expect a thread created with identifier A
    /// - Expect thread's last message is B
    /// - Expect thread has the root event
    /// - Expect thread's number of replies is 1
    func testStartingThread() {
        let store = MXMemoryStore()
        testData.doMXSessionTest(withBobAndARoom: self, andStore: store) { bobSession, initialRoom, expectation in
            guard let bobSession = bobSession,
                  let initialRoom = initialRoom,
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                return
            }
            guard let threadingService = bobSession.threadingService else {
                XCTFail("Threading service must be created")
                expectation.fulfill()
                return
            }
            
            var localEcho: MXEvent?
            initialRoom.sendTextMessage("Root message", threadId: nil, localEcho: &localEcho) { response in
                switch response {
                case .success(let eventId):
                    guard let threadIdentifier = eventId else {
                        XCTFail("Failed to setup test conditions")
                        expectation.fulfill()
                        return
                    }
                    
                    initialRoom.sendTextMessage("Thread message", threadId: threadIdentifier, localEcho: &localEcho) { response2 in
                        switch response2 {
                        case .success(let eventId):
                            var observer: NSObjectProtocol?
                            observer = NotificationCenter.default.addObserver(forName: MXThreadingService.newThreadCreated,
                                                                              object: nil,
                                                                              queue: .main) { notification in
                                if let observer = observer {
                                    NotificationCenter.default.removeObserver(observer)
                                }
                                guard let thread = threadingService.thread(withId: threadIdentifier) else {
                                    XCTFail("Thread must be created")
                                    expectation.fulfill()
                                    return
                                }
                                
                                XCTAssertEqual(thread.identifier, threadIdentifier, "Thread must have the correctid")
                                XCTAssertEqual(thread.roomId, initialRoom.roomId, "Thread must have the correct room id")
                                XCTAssertEqual(thread.lastMessage?.eventId, eventId, "Thread last message must have the correct event id")
                                XCTAssertNotNil(thread.rootMessage, "Thread must have the root event")
                                XCTAssertEqual(thread.numberOfReplies, 1, "Thread must have only 1 reply")
                                
                                expectation.fulfill()
                            }
                        case .failure(let error):
                            XCTFail("Failed to setup test conditions: \(error)")
                            expectation.fulfill()
                        }
                    }
                    
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
    
    /// Test: Expect a thread is updated after sending multiple events to the thread
    /// - Create a Bob session
    /// - Create an initial room
    /// - Send a text message A to be used as thread root event
    /// - Send a threaded event B referencing the root event A
    /// - Expect a thread created with identifier A
    /// - Send threaded events [C, D] referencing the root event A
    /// - Wait for a sync, for events to be processed by the threading service
    /// - Expect thread's last message is D
    /// - Expect thread has the root event
    /// - Expect thread's number of replies is 3 (replies should be B, C, D)
    func testUpdatingThread() {
        let store = MXMemoryStore()
        testData.doMXSessionTest(withBobAndARoom: self, andStore: store) { bobSession, initialRoom, expectation in
            guard let bobSession = bobSession,
                  let initialRoom = initialRoom,
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                return
            }
            guard let threadingService = bobSession.threadingService else {
                XCTFail("Threading service must be created")
                expectation.fulfill()
                return
            }
            
            var localEcho: MXEvent?
            initialRoom.sendTextMessage("Root message", threadId: nil, localEcho: &localEcho) { response in
                switch response {
                case .success(let eventId):
                    guard let threadIdentifier = eventId else {
                        XCTFail("Failed to setup test conditions")
                        expectation.fulfill()
                        return
                    }
                    
                    initialRoom.sendTextMessage("Thread message 1",
                                                threadId: threadIdentifier,
                                                localEcho: &localEcho) { response2 in
                        switch response2 {
                        case .success:
                            var observer: NSObjectProtocol?
                            observer = NotificationCenter.default.addObserver(forName: MXThreadingService.newThreadCreated,
                                                                              object: nil,
                                                                              queue: .main) { notification in
                                if let observer = observer {
                                    NotificationCenter.default.removeObserver(observer)
                                }
                                guard let thread = threadingService.thread(withId: threadIdentifier) else {
                                    XCTFail("Thread must be created")
                                    expectation.fulfill()
                                    return
                                }
                                
                                initialRoom.sendTextMessages(messages: ["Thread message 2", "Thread message 3"],
                                                             threadId: threadIdentifier) { response3 in
                                    switch response3 {
                                    case .success(let eventIds):
                                        var syncObserver: NSObjectProtocol?
                                        syncObserver = NotificationCenter.default.addObserver(forName: .mxSessionDidSync,
                                                                                              object: nil,
                                                                                              queue: .main) { notification in
                                            if let syncObserver = syncObserver {
                                                NotificationCenter.default.removeObserver(syncObserver)
                                            }
                                            
                                            XCTAssertEqual(thread.identifier, threadIdentifier, "Thread must have the correctid")
                                            XCTAssertEqual(thread.roomId, initialRoom.roomId, "Thread must have the correct room id")
                                            XCTAssertEqual(thread.lastMessage?.eventId, eventIds.last, "Thread last message must have the correct event id")
                                            XCTAssertNotNil(thread.rootMessage, "Thread must have the root event")
                                            XCTAssertEqual(thread.numberOfReplies, 3, "Thread must have 3 replies")
                                            
                                            expectation.fulfill()
                                        }
                                    case .failure(let error):
                                        XCTFail("Failed to setup test conditions: \(error)")
                                        expectation.fulfill()
                                    }
                                }
                            }
                        case .failure(let error):
                            XCTFail("Failed to setup test conditions: \(error)")
                            expectation.fulfill()
                        }
                    }
                    
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                    expectation.fulfill()
                }
            }
        }
    }

    /// Test: Expect a reply to an event in a thread is also in the same thread
    /// - Create a Bob session
    /// - Create an initial room
    /// - Send a text message A to be used as thread root event
    /// - Send a threaded event B referencing the root event A
    /// - Expect a thread created with identifier A
    /// - Send a reply to event B
    /// - Wait for a sync for the reply to be processed
    /// - Expect the reply event is also in the thread A
    func testReplyingInThread() {
        let store = MXMemoryStore()
        testData.doMXSessionTest(withBobAndARoom: self, andStore: store) { bobSession, initialRoom, expectation in
            guard let bobSession = bobSession,
                  let initialRoom = initialRoom,
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                return
            }
            guard let threadingService = bobSession.threadingService else {
                XCTFail("Threading service must be created")
                expectation.fulfill()
                return
            }
            
            var localEcho: MXEvent?
            initialRoom.sendTextMessage("Root message", threadId: nil, localEcho: &localEcho) { response in
                switch response {
                case .success(let eventId):
                    guard let threadIdentifier = eventId else {
                        XCTFail("Failed to setup test conditions")
                        expectation.fulfill()
                        return
                    }
                    
                    initialRoom.sendTextMessage("Thread message", threadId: threadIdentifier, localEcho: &localEcho) { response2 in
                        switch response2 {
                        case .success(let lastEventId):
                            var observer: NSObjectProtocol?
                            observer = NotificationCenter.default.addObserver(forName: MXThreadingService.newThreadCreated,
                                                                              object: nil,
                                                                              queue: .main) { notification in
                                if let observer = observer {
                                    NotificationCenter.default.removeObserver(observer)
                                }
                                guard let thread = threadingService.thread(withId: threadIdentifier),
                                      let lastMessage = thread.lastMessage else {
                                    XCTFail("Thread must be created with a last message")
                                    expectation.fulfill()
                                    return
                                }
                                
                                initialRoom.sendReply(to: lastMessage, textMessage: "Reply message", formattedTextMessage: nil, stringLocalizer: nil, localEcho: &localEcho) { response3 in
                                    switch response3 {
                                    case .success(let replyEventId):
                                        var syncObserver: NSObjectProtocol?
                                        syncObserver = NotificationCenter.default.addObserver(forName: .mxSessionDidSync,
                                                                                              object: nil,
                                                                                              queue: .main) { notification in
                                            if let syncObserver = syncObserver {
                                                NotificationCenter.default.removeObserver(syncObserver)
                                            }
                                            
                                            guard let replyEvent = store.event(withEventId: replyEventId!, inRoom: thread.roomId) else {
                                                XCTFail("Reply event must be found in the store")
                                                expectation.fulfill()
                                                return
                                            }
                                            
                                            XCTAssertEqual(replyEvent.threadIdentifier, threadIdentifier, "Reply must also be in the thread")
                                            
                                            guard let relatesTo = replyEvent.content[kMXEventRelationRelatesToKey] as? [String: Any],
                                                  let inReplyTo = relatesTo["m.in_reply_to"] as? [String: String] else {
                                                XCTFail("Reply event must have a reply-to dictionary in the content")
                                                expectation.fulfill()
                                                return
                                            }
                                            XCTAssertEqual(inReplyTo["event_id"], lastEventId, "Reply must point to the last message event")
                                            
                                            expectation.fulfill()
                                        }
                                    case .failure(let error):
                                        XCTFail("Failed to setup test conditions: \(error)")
                                        expectation.fulfill()
                                    }
                                }
                            }
                        case .failure(let error):
                            XCTFail("Failed to setup test conditions: \(error)")
                            expectation.fulfill()
                        }
                    }
                    
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
    
    /// Test: Expect a thread is listed in the thread list after sending an event to a thread
    /// - Create a Bob session
    /// - Create an initial room
    /// - Send a text message A to be used as thread root event
    /// - Send a threaded event B referencing the root event A
    /// - Expect a thread created with identifier A
    /// - Expect thread's last message is B
    /// - Expect thread has the root event
    /// - Expect thread's number of replies is 1
    func testThreadListSingleItem() {
        let store = MXMemoryStore()
        testData.doMXSessionTest(withBobAndARoom: self, andStore: store) { bobSession, initialRoom, expectation in
            guard let bobSession = bobSession,
                  let initialRoom = initialRoom,
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                expectation?.fulfill()
                return
            }
            guard let threadingService = bobSession.threadingService else {
                XCTFail("Threading service must be created")
                expectation.fulfill()
                return
            }
            
            var localEcho: MXEvent?
            initialRoom.sendTextMessage("Root message",
                                        threadId: nil,
                                        localEcho: &localEcho) { response in
                switch response {
                case .success(let eventId):
                    guard let threadIdentifier = eventId else {
                        XCTFail("Failed to setup test conditions")
                        expectation.fulfill()
                        return
                    }
                    
                    initialRoom.sendTextMessage("Thread message", threadId: threadIdentifier, localEcho: &localEcho) { response2 in
                        switch response2 {
                        case .success(let eventId):
                            var observer: NSObjectProtocol?
                            observer = NotificationCenter.default.addObserver(forName: MXThreadingService.newThreadCreated,
                                                                              object: nil,
                                                                              queue: .main) { notification in
                                if let observer = observer {
                                    NotificationCenter.default.removeObserver(observer)
                                }
                                guard let thread = threadingService.threads(inRoom: initialRoom.roomId).first else {
                                    XCTFail("Thread must be created")
                                    expectation.fulfill()
                                    return
                                }
                                
                                XCTAssertEqual(thread.identifier, threadIdentifier, "Thread must have the correctid")
                                XCTAssertEqual(thread.roomId, initialRoom.roomId, "Thread must have the correct room id")
                                XCTAssertEqual(thread.lastMessage?.eventId, eventId, "Thread last message must have the correct event id")
                                XCTAssertNotNil(thread.rootMessage, "Thread must have the root event")
                                XCTAssertEqual(thread.numberOfReplies, 1, "Thread must have only 1 reply")
                                XCTAssertTrue(thread.isParticipated, "Thread must be participated")
                                
                                expectation.fulfill()
                            }
                        case .failure(let error):
                            XCTFail("Failed to setup test conditions: \(error)")
                            expectation.fulfill()
                        }
                    }
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
    
    /// Test: Expect a thread list has a correct sorting
    /// - Create a Bob session
    /// - Create an initial room
    /// - Send a text message A to be used as thread root event
    /// - Send a threaded event B referencing the root event A
    /// - Expect a thread created with identifier A
    /// - Send a text message C to be used as thread root event
    /// - Send a threaded event D referencing the root event C
    /// - Expect a thread created with identifier C
    /// - Fetch all threads in the room
    /// - Expect thread C is first thread
    /// - Expect thread A is the last thread
    /// - Fetch participated threads in the room
    /// - Expect thread C is first thread
    /// - Expect thread A is the last thread
    func testThreadListSortingAndFiltering() {
        let store = MXMemoryStore()
        testData.doMXSessionTest(withBobAndARoom: self, andStore: store) { bobSession, initialRoom, expectation in
            guard let bobSession = bobSession,
                  let initialRoom = initialRoom,
                  let expectation = expectation else {
                XCTFail("Failed to setup test conditions")
                expectation?.fulfill()
                return
            }
            guard let threadingService = bobSession.threadingService else {
                XCTFail("Threading service must be created")
                expectation.fulfill()
                return
            }
            
            var localEcho: MXEvent?
            initialRoom.sendTextMessage("Root message 1",
                                        threadId: nil,
                                        localEcho: &localEcho) { response in
                switch response {
                case .success(let eventId):
                    guard let threadIdentifier1 = eventId else {
                        XCTFail("Failed to setup test conditions")
                        expectation.fulfill()
                        return
                    }
                    
                    initialRoom.sendTextMessage("Thread message 1", threadId: threadIdentifier1, localEcho: &localEcho) { response2 in
                        switch response2 {
                        case .success:
                            var observer: NSObjectProtocol?
                            observer = NotificationCenter.default.addObserver(forName: MXThreadingService.newThreadCreated,
                                                                              object: nil,
                                                                              queue: .main) { notification in
                                if let observer = observer {
                                    NotificationCenter.default.removeObserver(observer)
                                }
                                
                                initialRoom.sendTextMessage("Root message 2",
                                                            threadId: nil,
                                                            localEcho: &localEcho) { response in
                                    switch response {
                                    case .success(let eventId):
                                        guard let threadIdentifier2 = eventId else {
                                            XCTFail("Failed to setup test conditions")
                                            expectation.fulfill()
                                            return
                                        }
                                        
                                        initialRoom.sendTextMessage("Thread message 2", threadId: threadIdentifier2, localEcho: &localEcho) { response2 in
                                            switch response2 {
                                            case .success:
                                                var observer: NSObjectProtocol?
                                                observer = NotificationCenter.default.addObserver(forName: MXThreadingService.newThreadCreated,
                                                                                                  object: nil,
                                                                                                  queue: .main) { notification in
                                                    if let observer = observer {
                                                        NotificationCenter.default.removeObserver(observer)
                                                    }
                                                    let threads = threadingService.threads(inRoom: initialRoom.roomId)
                                                    
                                                    XCTAssertEqual(threads.count, 2, "Must have 2 threads")
                                                    XCTAssertEqual(threads.first?.identifier, threadIdentifier2, "Latest thread must be in the first position")
                                                    XCTAssertEqual(threads.last?.identifier, threadIdentifier1, "Older thread must be in the last position")
                                                    
                                                    let participatedThreads = threadingService.participatedThreads(inRoom: initialRoom.roomId)
                                                    
                                                    XCTAssertEqual(participatedThreads.count, 2, "Must have 2 participated threads")
                                                    XCTAssertEqual(participatedThreads.first?.identifier, threadIdentifier2, "Latest thread must be in the first position")
                                                    XCTAssertEqual(participatedThreads.last?.identifier, threadIdentifier1, "Older thread must be in the last position")
                                                    
                                                    expectation.fulfill()
                                                }
                                            case .failure(let error):
                                                XCTFail("Failed to setup test conditions: \(error)")
                                                expectation.fulfill()
                                            }
                                        }
                                    case .failure(let error):
                                        XCTFail("Failed to setup test conditions: \(error)")
                                        expectation.fulfill()
                                    }
                                }
                                
                                expectation.fulfill()
                            }
                        case .failure(let error):
                            XCTFail("Failed to setup test conditions: \(error)")
                            expectation.fulfill()
                        }
                    }
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                    expectation.fulfill()
                }
            }
        }
    }
}
