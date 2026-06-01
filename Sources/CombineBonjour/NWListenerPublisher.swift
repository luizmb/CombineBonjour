// Copyright © 2024 Lautsprecher Teufel GmbH. All rights reserved.

import Combine
import Foundation
import Network

extension NWListener {
    public var publisher: NWListenerPublisher {
        .init(listener: self)
    }
}

public struct NWListenerPublisher {
    private let listener: NWListener

    /// Use an already-configured `NWListener`. All handlers will be overwritten on subscription.
    public init(listener: NWListener) {
        self.listener = listener
    }

    /// Convenience: creates and configures an `NWListener` that advertises a Bonjour service.
    ///
    /// - Parameters:
    ///   - serviceType: Bonjour service type, e.g. `"_myapp._tcp."`.
    ///   - serviceName: Human-readable service name; `nil` defaults to the device name.
    ///   - port: Port to listen on; `.any` lets the OS assign one (reported in the `.ready` event).
    ///   - txtRecord: Optional TXT record metadata advertised alongside the service.
    ///   - params: Network parameters; defaults to plain TCP.
    /// - Throws: `NWError` if the port is already in use or otherwise unavailable.
    public init(
        serviceType: String,
        serviceName: String? = nil,
        port: NWEndpoint.Port = .any,
        txtRecord: NWTXTRecord = NWTXTRecord(),
        params: NWParameters = .tcp
    ) throws {
        let l = try NWListener(using: params, on: port)
        l.service = NWListener.Service(name: serviceName, type: serviceType, domain: nil, txtRecord: txtRecord)
        self.listener = l
    }
}

extension NWListenerPublisher: Publisher {
    public typealias Output = Event
    public typealias Failure = NWListenerError

    public func receive<S>(subscriber: S) where S: Subscriber, Failure == S.Failure, Output == S.Input {
        subscriber.receive(subscription: Subscription(subscriber: subscriber, listener: listener))
    }
}

extension NWListenerPublisher {
    private class Subscription<SubscriberType: Subscriber>: Combine.Subscription
    where SubscriberType.Input == Output, SubscriberType.Failure == Failure {
        private var buffer: DemandBuffer<SubscriberType>?
        private let listener: NWListener

        private let lock = NSRecursiveLock()
        // Side-effects start only when there is demand for the first time.
        private var started = false

        init(subscriber: SubscriberType, listener: NWListener) {
            self.listener = listener
            self.buffer = DemandBuffer(subscriber: subscriber)

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .setup:
                    break
                case .ready:
                    _ = buffer?.buffer(value: .ready(port: listener.port))
                case let .waiting(error):
                    handleError(error)
                case let .failed(error):
                    handleError(error)
                case .cancelled:
                    buffer?.complete(completion: .finished)
                @unknown default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                _ = self?.buffer?.buffer(value: .newConnection(connection))
            }

            listener.serviceRegistrationUpdateHandler = { [weak self] change in
                _ = self?.buffer?.buffer(value: .serviceRegistrationChanged(change))
            }
        }

        func request(_ demand: Subscribers.Demand) {
            guard let buffer else { return }

            lock.lock()
            if !started && demand > .none {
                started = true
                lock.unlock()
                start()
            } else {
                lock.unlock()
            }
            _ = buffer.demand(demand)
        }

        func cancel() {
            buffer = nil
            started = false
            stop()
        }

        private func start() {
            listener.start(queue: .main)
        }

        private func stop() {
            listener.cancel()
        }

        private func handleError(_ error: NWError) {
            if case let .dns(code) = error, code == kDNSServiceErr_PolicyDenied {
                buffer?.complete(completion: .failure(.permissionDenied))
            } else {
                buffer?.complete(completion: .failure(.failed(error: error)))
            }
        }
    }
}

// MARK: - Model

extension NWListenerPublisher {
    public enum Event {
        /// The listener is active and advertising via Bonjour. `port` is the OS-assigned port —
        /// always check this when the listener was created with `.any`.
        case ready(port: NWEndpoint.Port?)

        /// A client has connected. Callers must call `connection.start(queue:)` to begin I/O.
        case newConnection(NWConnection)

        /// Bonjour service registration status changed (added or removed on the local network).
        case serviceRegistrationChanged(NWListener.ServiceRegistrationChange)
    }

    public enum NWListenerError: Error {
        /// Local network access was denied by the OS or user.
        case permissionDenied

        /// The listener failed with the given network error.
        case failed(error: NWError)
    }
}
