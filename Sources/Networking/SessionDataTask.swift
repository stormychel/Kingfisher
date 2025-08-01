//
//  SessionDataTask.swift
//  Kingfisher
//
//  Created by Wei Wang on 2018/11/1.
//
//  Copyright (c) 2019 Wei Wang <onevcat@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation

/// Represents a session data task in ``ImageDownloader``.
///
/// Essentially, a ``SessionDataTask`` wraps a `URLSessionDataTask` and manages the download data.
/// It uses a ``SessionDataTask/CancelToken`` to track the task and manage its cancellation.
public class SessionDataTask: @unchecked Sendable {

    /// Represents the type of token used for canceling a task.
    public typealias CancelToken = Int

    struct TaskCallback {
        let onCompleted: Delegate<Result<ImageLoadingResult, KingfisherError>, Void>?
        let options: KingfisherParsedOptionsInfo
    }

    private var _mutableData: Data
    /// The downloaded raw data of the current task.
    public var mutableData: Data {
        lock.lock()
        defer { lock.unlock() }
        return _mutableData
    }

    // This is a copy of `task.originalRequest?.url`. It is for obtaining race-safe behavior for a pitfall on iOS 13.
    // Ref: https://github.com/onevcat/Kingfisher/issues/1511
    public let originalURL: URL?

    /// The underlying download task. 
    ///
    /// It is only for debugging purposes when you encounter an error. You should not modify the content of this task
    /// or start it yourself.
    public let task: URLSessionDataTask
    
    private var callbacksStore = [CancelToken: TaskCallback]()

    var callbacks: [SessionDataTask.TaskCallback] {
        lock.lock()
        defer { lock.unlock() }
        return Array(callbacksStore.values)
    }

    private var currentToken = 0
    private let lock = NSLock()
    
    private var _metrics: NetworkMetrics?
    /// The network metrics collected during the download task.
    public var metrics: NetworkMetrics? {
        lock.lock()
        defer { lock.unlock() }
        return _metrics
    }

    let onTaskDone = Delegate<(Result<(Data, URLResponse?), KingfisherError>, [TaskCallback]), Void>()
    let onCallbackCancelled = Delegate<(CancelToken, TaskCallback), Void>()

    var started = false
    var containsCallbacks: Bool {
        // We should be able to use `task.state != .running` to check it.
        // However, in some rare cases, cancelling the task does not change
        // task state to `.cancelling` immediately, but still in `.running`.
        // So we need to check callbacks count to for sure that it is safe to remove the
        // task in delegate.
        return !callbacks.isEmpty
    }

    init(task: URLSessionDataTask) {
        self.task = task
        self.originalURL = task.originalRequest?.url
        _mutableData = Data()
    }

    func addCallback(_ callback: TaskCallback) -> CancelToken {
        lock.lock()
        defer { lock.unlock() }
        callbacksStore[currentToken] = callback
        defer { currentToken += 1 }
        return currentToken
    }

    func removeCallback(_ token: CancelToken) -> TaskCallback? {
        lock.lock()
        defer { lock.unlock() }
        if let callback = callbacksStore[token] {
            callbacksStore[token] = nil
            return callback
        }
        return nil
    }
    
    @discardableResult
    func removeAllCallbacks() -> [TaskCallback] {
        lock.lock()
        defer { lock.unlock() }
        let callbacks = callbacksStore.values
        callbacksStore.removeAll()
        return Array(callbacks)
    }

    func resume() {
        guard !started else { return }
        started = true
        task.resume()
    }

    func cancel(token: CancelToken) {
        guard let callback = removeCallback(token) else {
            return
        }
        onCallbackCancelled.call((token, callback))
    }

    func forceCancel() {
        for token in callbacksStore.keys {
            cancel(token: token)
        }
    }

    func didReceiveData(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        _mutableData.append(data)
    }
    
    func didCollectMetrics(_ metrics: NetworkMetrics) {
        lock.lock()
        defer { lock.unlock() }
        _metrics = metrics
    }
}
