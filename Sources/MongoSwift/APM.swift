import Foundation
import mongoc

/// A protocol for monitoring events to implement, specifying their name.
public protocol MongoEvent {
    /// The name this event will be posted under.
    static var eventName: Notification.Name { get }
}

/// A protocol for command monitoring events to implement, specifying the command name and other shared fields.
public protocol MongoCommandEvent: MongoEvent {
    /// The command name.
    var commandName: String { get }

    /// The driver generated request id.
    var requestId: Int64 { get }

    /// The driver generated operation id. This is used to link events together such
    /// as bulk write operations.
    var operationId: Int64 { get }

    /// The connection id for the command.
    var connectionId: ConnectionId { get }
}

/// A protocol for monitoring events to implement, indicating that they can be initialized from an OpaquePointer
/// to the corresponding libmongoc type.
private protocol InitializableFromOpaquePointer {
    /// Initializes the event from an OpaquePointer.
    init(_ event: OpaquePointer)
}

/// An event published when a command starts. The event is stored under the key `event`
/// in the `userInfo` property of `Notification`s posted under the name .commandStarted.
public struct CommandStartedEvent: MongoCommandEvent, InitializableFromOpaquePointer {
    /// The name this event will be posted under.
    public static var eventName: Notification.Name { return .commandStarted }

    /// The command.
    public let command: Document

    /// The database name.
    public let databaseName: String

    /// The command name.
    public let commandName: String

    /// The driver generated request id.
    public let requestId: Int64

    /// The driver generated operation id. This is used to link events together such
    /// as bulk write operations.
    public let operationId: Int64

    /// The connection id for the command.
    public let connectionId: ConnectionId

    /// Initializes a CommandStartedEvent from an OpaquePointer to a mongoc_apm_command_started_t
    fileprivate init(_ event: OpaquePointer) {
        // we have to copy because libmongoc owns the pointer.
        self.command = Document(copying: mongoc_apm_command_started_get_command(event))
        self.databaseName = String(cString: mongoc_apm_command_started_get_database_name(event))
        self.commandName = String(cString: mongoc_apm_command_started_get_command_name(event))
        self.requestId = mongoc_apm_command_started_get_request_id(event)
        self.operationId = mongoc_apm_command_started_get_operation_id(event)
        self.connectionId = ConnectionId(mongoc_apm_command_started_get_host(event))
    }
}

/// An event published when a command succeeds. The event is stored under the key `event`
/// in the `userInfo` property of `Notification`s posted under the name .commandSucceeded.
public struct CommandSucceededEvent: MongoCommandEvent, InitializableFromOpaquePointer {
    /// The name this event will be posted under.
    public static var eventName: Notification.Name { return .commandSucceeded }

    /// The execution time of the event, in microseconds.
    public let duration: Int64

    /// The command reply.
    public let reply: Document

    /// The command name.
    public let commandName: String

    /// The driver generated request id.
    public let requestId: Int64

    /// The driver generated operation id. This is used to link events together such
    /// as bulk write operations.
    public let operationId: Int64

    /// The connection id for the command.
    public let connectionId: ConnectionId

    /// Initializes a CommandSucceededEvent from an OpaquePointer to a mongoc_apm_command_succeeded_t
    fileprivate init(_ event: OpaquePointer) {
        self.duration = mongoc_apm_command_succeeded_get_duration(event)
        // we have to copy because libmongoc owns the pointer.
        self.reply = Document(copying: mongoc_apm_command_succeeded_get_reply(event))
        self.commandName = String(cString: mongoc_apm_command_succeeded_get_command_name(event))
        self.requestId = mongoc_apm_command_succeeded_get_request_id(event)
        self.operationId = mongoc_apm_command_succeeded_get_operation_id(event)
        self.connectionId = ConnectionId(mongoc_apm_command_succeeded_get_host(event))
    }
}

/// An event published when a command fails. The event is stored under the key `event`
/// in the `userInfo` property of `Notification`s posted under the name .commandFailed.
public struct CommandFailedEvent: MongoCommandEvent, InitializableFromOpaquePointer {
    /// The name this event will be posted under.
    public static var eventName: Notification.Name { return .commandFailed }

    /// The execution time of the event, in microseconds.
    public let duration: Int64

    /// The command name.
    public let commandName: String

    /// The failure, represented as a MongoError.
    public let failure: MongoError

    /// The client generated request id.
    public let requestId: Int64

    /// The driver generated operation id. This is used to link events together such
    /// as bulk write operations.
    public let operationId: Int64

    /// The connection id for the command.
    public let connectionId: ConnectionId

    /// Initializes a CommandFailedEvent from an OpaquePointer to a mongoc_apm_command_failed_t
    fileprivate init(_ event: OpaquePointer) {
        self.duration = mongoc_apm_command_failed_get_duration(event)
        self.commandName = String(cString: mongoc_apm_command_failed_get_command_name(event))
        var error = bson_error_t()
        mongoc_apm_command_failed_get_error(event, &error)
        let reply = Document(copying: mongoc_apm_command_failed_get_reply(event))
        self.failure = extractMongoError(error: error, reply: reply) // should always return a CommandError
        self.requestId = mongoc_apm_command_failed_get_request_id(event)
        self.operationId = mongoc_apm_command_failed_get_operation_id(event)
        self.connectionId = ConnectionId(mongoc_apm_command_failed_get_host(event))
    }
}

/// Published when a server description changes. This does NOT include changes to the server's roundTripTime property.
public struct ServerDescriptionChangedEvent: MongoEvent, InitializableFromOpaquePointer {
    /// The name this event will be posted under.
    public static var eventName: Notification.Name { return .serverDescriptionChanged }

    /// The connection ID (host/port pair) of the server.
    public let connectionId: ConnectionId

    /// A unique identifier for the topology.
    public let topologyId: ObjectId

    /// The previous server description.
    public let previousDescription: ServerDescription

    /// The new server description.
    public let newDescription: ServerDescription

    /// Initializes a ServerDescriptionChangedEvent from an OpaquePointer to a mongoc_server_changed_t
    fileprivate init(_ event: OpaquePointer) {
        self.connectionId = ConnectionId(mongoc_apm_server_changed_get_host(event))
        var oid = bson_oid_t()
        withUnsafeMutablePointer(to: &oid) { oidPtr in
            mongoc_apm_server_changed_get_topology_id(event, oidPtr)
        }
        self.topologyId = ObjectId(bsonOid: oid)
        self.previousDescription = ServerDescription(mongoc_apm_server_changed_get_previous_description(event))
        self.newDescription = ServerDescription(mongoc_apm_server_changed_get_new_description(event))
    }
}

/// Published when a server is initialized.
public struct ServerOpeningEvent: MongoEvent, InitializableFromOpaquePointer {
    /// The name this event will be posted under.
    public static var eventName: Notification.Name { return .serverOpening }

    /// The connection ID (host/port pair) of the server.
    public let connectionId: ConnectionId

    /// A unique identifier for the topology.
    public let topologyId: ObjectId

    /// Initializes a ServerOpeningEvent from an OpaquePointer to a mongoc_apm_server_opening_t
    fileprivate init(_ event: OpaquePointer) {
        self.connectionId = ConnectionId(mongoc_apm_server_opening_get_host(event))
        var oid = bson_oid_t()
        withUnsafeMutablePointer(to: &oid) { oidPtr in
            mongoc_apm_server_opening_get_topology_id(event, oidPtr)
        }
        self.topologyId = ObjectId(bsonOid: oid)
    }
}

/// Published when a server is closed.
public struct ServerClosedEvent: MongoEvent, InitializableFromOpaquePointer {
    /// The name this event will be posted under.
    public static var eventName: Notification.Name { return .serverClosed }

    /// The connection ID (host/port pair) of the server.
    public let connectionId: ConnectionId

    /// A unique identifier for the topology.
    public let topologyId: ObjectId

    /// Initializes a TopologyClosedEvent from an OpaquePointer to a mongoc_apm_topology_closed_t
    fileprivate init(_ event: OpaquePointer) {
        self.connectionId = ConnectionId(mongoc_apm_server_closed_get_host(event))
        var oid = bson_oid_t()
        withUnsafeMutablePointer(to: &oid) { oidPtr in
            mongoc_apm_server_closed_get_topology_id(event, oidPtr)
        }
        self.topologyId = ObjectId(bsonOid: oid)
    }
}

/// Published when a topology description changes.
public struct TopologyDescriptionChangedEvent: MongoEvent, InitializableFromOpaquePointer {
    /// The name this event will be posted under.
    public static var eventName: Notification.Name { return .topologyDescriptionChanged }

    /// A unique identifier for the topology.
    public let topologyId: ObjectId

    /// The old topology description.
    public let previousDescription: TopologyDescription

    /// The new topology description.
    public let newDescription: TopologyDescription

    /// Initializes a TopologyDescriptionChangedEvent from an OpaquePointer to a mongoc_apm_topology_changed_t
    fileprivate init(_ event: OpaquePointer) {
        var oid = bson_oid_t()
        withUnsafeMutablePointer(to: &oid) { oidPtr in
            mongoc_apm_topology_changed_get_topology_id(event, oidPtr)
        }
        self.topologyId = ObjectId(bsonOid: oid)
        self.previousDescription = TopologyDescription(mongoc_apm_topology_changed_get_previous_description(event))
        self.newDescription = TopologyDescription(mongoc_apm_topology_changed_get_new_description(event))
    }
}

/// Published when a topology is initialized.
public struct TopologyOpeningEvent: MongoEvent, InitializableFromOpaquePointer {
    /// The name this event will be posted under.
    public static var eventName: Notification.Name { return .topologyOpening }

    /// A unique identifier for the topology.
    public let topologyId: ObjectId

    /// Initializes a TopologyOpeningEvent from an OpaquePointer to a mongoc_apm_topology_opening_t
    fileprivate init(_ event: OpaquePointer) {
        var oid = bson_oid_t()
        withUnsafeMutablePointer(to: &oid) { oidPtr in
            mongoc_apm_topology_opening_get_topology_id(event, oidPtr)
        }
        self.topologyId = ObjectId(bsonOid: oid)
    }
}

/// Published when a topology is closed.
public struct TopologyClosedEvent: MongoEvent, InitializableFromOpaquePointer {
    /// The name this event will be posted under.
    public static var eventName: Notification.Name { return .topologyClosed }

    /// A unique identifier for the topology.
    public let topologyId: ObjectId

    /// Initializes a TopologyClosedEvent from an OpaquePointer to a mongoc_apm_topology_closed_t
    fileprivate init(_ event: OpaquePointer) {
        var oid = bson_oid_t()
        withUnsafeMutablePointer(to: &oid) { oidPtr in
            mongoc_apm_topology_closed_get_topology_id(event, oidPtr)
        }
        self.topologyId = ObjectId(bsonOid: oid)
    }
}

/// Published when the server monitor’s ismaster command is started - immediately before
/// the ismaster command is serialized into raw BSON and written to the socket.
public struct ServerHeartbeatStartedEvent: MongoEvent, InitializableFromOpaquePointer {
    /// The name this event will be posted under.
    public static var eventName: Notification.Name { return .serverHeartbeatStarted }

    /// The connection ID (host/port pair) of the server.
    public let connectionId: ConnectionId

    /// Initializes a ServerHeartbeatStartedEvent from an OpaquePointer to a mongoc_apm_server_heartbeat_started_t
    fileprivate init(_ event: OpaquePointer) {
        self.connectionId = ConnectionId(mongoc_apm_server_heartbeat_started_get_host(event))
    }
}

/// Published when the server monitor’s ismaster succeeds.
public struct ServerHeartbeatSucceededEvent: MongoEvent, InitializableFromOpaquePointer {
    /// The name this event will be posted under.
    public static var eventName: Notification.Name { return .serverHeartbeatSucceeded }

    /// The execution time of the event, in microseconds.
    public let duration: Int64

    /// The command reply.
    public let reply: Document

    /// The connection ID (host/port pair) of the server.
    public let connectionId: ConnectionId

    /// Initializes a ServerHeartbeatSucceededEvent from an OpaquePointer to a mongoc_apm_server_heartbeat_succeeded_t
    fileprivate init(_ event: OpaquePointer) {
        self.duration = mongoc_apm_server_heartbeat_succeeded_get_duration(event)
        // we have to copy because libmongoc owns the pointer.
        self.reply = Document(copying: mongoc_apm_server_heartbeat_succeeded_get_reply(event))
        self.connectionId = ConnectionId(mongoc_apm_server_heartbeat_succeeded_get_host(event))
    }
}

/// Published when the server monitor’s ismaster fails, either with an “ok: 0” or a socket exception.
public struct ServerHeartbeatFailedEvent: MongoEvent, InitializableFromOpaquePointer {
    /// The name this event will be posted under.
    public static var eventName: Notification.Name { return .serverHeartbeatFailed }

    /// The execution time of the event, in microseconds.
    public let duration: Int64

    /// The failure.
    public let failure: MongoError

    /// The connection ID (host/port pair) of the server.
    public let connectionId: ConnectionId

    /// Initializes a ServerHeartbeatFailedEvent from an OpaquePointer to a mongoc_apm_server_heartbeat_failed_t
    fileprivate init(_ event: OpaquePointer) {
        self.duration = mongoc_apm_server_heartbeat_failed_get_duration(event)
        var error = bson_error_t()
        mongoc_apm_server_heartbeat_failed_get_error(event, &error)
        self.failure = extractMongoError(error: error)
        self.connectionId = ConnectionId(mongoc_apm_server_heartbeat_failed_get_host(event))
    }
}

/// Callbacks that will be set for events with the corresponding names if the user enables
/// notifications for those events. These functions generate new `Notification`s and post
/// them to the `NotificationCenter` that was by the user, or `NotificationCenter.default`
/// if none was specified.

/// A callback that will be set for "command started" events if the user enables command monitoring.
private func commandStarted(_event: OpaquePointer?) {
    postNotification(
        type: CommandStartedEvent.self,
        _event: _event,
        contextFunc: mongoc_apm_command_started_get_context
    )
}

/// A callback that will be set for "command succeeded" events if the user enables command monitoring.
private func commandSucceeded(_event: OpaquePointer?) {
    postNotification(
        type: CommandSucceededEvent.self,
        _event: _event,
        contextFunc: mongoc_apm_command_succeeded_get_context
    )
}

/// A callback that will be set for "command failed" events if the user enables command monitoring.
private func commandFailed(_event: OpaquePointer?) {
    postNotification(
        type: CommandFailedEvent.self,
        _event: _event,
        contextFunc: mongoc_apm_command_failed_get_context
    )
}

/// A callback that will be set for "server description changed" events if the user enables server monitoring.
private func serverDescriptionChanged(_event: OpaquePointer?) {
    postNotification(
        type: ServerDescriptionChangedEvent.self,
        _event: _event,
        contextFunc: mongoc_apm_server_changed_get_context
    )
}

/// A callback that will be set for "server opening" events if the user enables server monitoring.
private func serverOpening(_event: OpaquePointer?) {
    postNotification(
        type: ServerOpeningEvent.self,
        _event: _event,
        contextFunc: mongoc_apm_server_opening_get_context
    )
}

/// A callback that will be set for "server closed" events if the user enables server monitoring.
private func serverClosed(_event: OpaquePointer?) {
    postNotification(
        type: ServerClosedEvent.self,
        _event: _event,
        contextFunc: mongoc_apm_server_closed_get_context
    )
}

/// A callback that will be set for "topology description changed" events if the user enables server monitoring.
private func topologyDescriptionChanged(_event: OpaquePointer?) {
    postNotification(
        type: TopologyDescriptionChangedEvent.self,
        _event: _event,
        contextFunc: mongoc_apm_topology_changed_get_context
    )
}

/// A callback that will be set for "topology opening" events if the user enables server monitoring.
private func topologyOpening(_event: OpaquePointer?) {
    postNotification(
        type: TopologyOpeningEvent.self,
        _event: _event,
        contextFunc: mongoc_apm_topology_opening_get_context
    )
}

/// A callback that will be set for "topology closed" events if the user enables server monitoring.
private func topologyClosed(_event: OpaquePointer?) {
    postNotification(
        type: TopologyClosedEvent.self,
        _event: _event,
        contextFunc: mongoc_apm_topology_closed_get_context
    )
}

/// A callback that will be set for "server heartbeat started" events if the user enables server monitoring.
private func serverHeartbeatStarted(_event: OpaquePointer?) {
    postNotification(
        type: ServerHeartbeatStartedEvent.self,
        _event: _event,
        contextFunc: mongoc_apm_server_heartbeat_started_get_context
    )
}

/// A callback that will be set for "server heartbeat succeeded" events if the user enables server monitoring.
private func serverHeartbeatSucceeded(_event: OpaquePointer?) {
    postNotification(
        type: ServerHeartbeatSucceededEvent.self,
        _event: _event,
        contextFunc: mongoc_apm_server_heartbeat_succeeded_get_context
    )
}

/// A callback that will be set for "server heartbeat failed" events if the user enables server monitoring.
private func serverHeartbeatFailed(_event: OpaquePointer?) {
    postNotification(
        type: ServerHeartbeatFailedEvent.self,
        _event: _event,
        contextFunc: mongoc_apm_server_heartbeat_failed_get_context
    )
}

/// Posts a Notification with the specified name, containing an event of type T generated using the provided _event
/// and context function.
private func postNotification<T: MongoEvent>(
    type: T.Type,
    _event: OpaquePointer?,
    contextFunc: (OpaquePointer) -> UnsafeMutableRawPointer?
) where T: InitializableFromOpaquePointer {
    guard let event = _event else {
        fatalError("Missing event pointer for \(type)")
    }

    let eventStruct = type.init(event)

    // TODO: SWIFT-524: remove workaround for CDRIVER-3256
    if let tdChanged = eventStruct as? TopologyDescriptionChangedEvent,
        tdChanged.previousDescription == tdChanged.newDescription {
        return
    }

    if let sdChanged = eventStruct as? ServerDescriptionChangedEvent,
        sdChanged.previousDescription == sdChanged.newDescription {
        return
    }

    guard let context = contextFunc(event) else {
        fatalError("Missing context for \(type)")
    }
    let client = Unmanaged<MongoClient>.fromOpaque(context).takeUnretainedValue()
    let notification = Notification(name: type.eventName, userInfo: ["event": eventStruct])
    client.notificationCenter.post(notification)
}

/// Extend Notification.Name to have class properties corresponding to each type
/// of event. This allows creating notifications and observers using these names.
extension Notification.Name {
    /// The name corresponding to a `CommandStartedEvent`.
    public static let commandStarted = Notification.Name(rawValue: "commandStarted")
    ///  The name corresponding to a `CommandSucceededEvent`.
    public static let commandSucceeded = Notification.Name(rawValue: "commandSucceeded")
    /// The name corresponding to a `CommandFailedEvent`.
    public static let commandFailed = Notification.Name(rawValue: "commandFailed")
    /// The name corresponding to a `ServerDescriptionChangedEvent`.
    public static let serverDescriptionChanged = Notification.Name(rawValue: "serverDescriptionChanged")
    /// The name corresponding to a `ServerOpeningEvent`.
    public static let serverOpening = Notification.Name(rawValue: "serverOpening")
    /// The name corresponding to a `ServerClosedEvent`.
    public static let serverClosed = Notification.Name(rawValue: "serverClosed")
    /// The name corresponding to a `TopologyDescriptionChangedEvent`.
    public static let topologyDescriptionChanged = Notification.Name(rawValue: "topologyDescriptionChanged")
    /// The name corresponding to a `TopologyOpeningEvent`.
    public static let topologyOpening = Notification.Name(rawValue: "topologyOpening")
    /// The name corresponding to a `TopologyClosedEvent`.
    public static let topologyClosed = Notification.Name(rawValue: "topologyClosed")
    /// The name corresponding to a `ServerHeartbeatStartedEvent`.
    public static let serverHeartbeatStarted = Notification.Name(rawValue: "serverHeartbeatStarted")
    /// The name corresponding to a `ServerHeartbeatSucceededEvent`.
    public static let serverHeartbeatSucceeded = Notification.Name(rawValue: "serverHeartbeatSucceeded")
    /// The name corresponding to a `ServerHeartbeatFailedEvent`.
    public static let serverHeartbeatFailed = Notification.Name(rawValue: "serverHeartbeatFailed")
}

/// An extension of `ConnectionPool` to add monitoring capability for commands and server discovery and monitoring.
extension ConnectionPool {
    /// Internal function to install monitoring callbacks for this pool.
    internal func initializeMonitoring(commandMonitoring: Bool, serverMonitoring: Bool, client: MongoClient) {
        guard let callbacks = mongoc_apm_callbacks_new() else {
            fatalError("failed to initialize new mongoc_apm_callbacks_t")
        }
        defer { mongoc_apm_callbacks_destroy(callbacks) }

        if commandMonitoring {
            mongoc_apm_set_command_started_cb(callbacks, commandStarted)
            mongoc_apm_set_command_succeeded_cb(callbacks, commandSucceeded)
            mongoc_apm_set_command_failed_cb(callbacks, commandFailed)
        }

        if serverMonitoring {
            mongoc_apm_set_server_changed_cb(callbacks, serverDescriptionChanged)
            mongoc_apm_set_server_opening_cb(callbacks, serverOpening)
            mongoc_apm_set_server_closed_cb(callbacks, serverClosed)
            mongoc_apm_set_topology_changed_cb(callbacks, topologyDescriptionChanged)
            mongoc_apm_set_topology_opening_cb(callbacks, topologyOpening)
            mongoc_apm_set_topology_closed_cb(callbacks, topologyClosed)
            mongoc_apm_set_server_heartbeat_started_cb(callbacks, serverHeartbeatStarted)
            mongoc_apm_set_server_heartbeat_succeeded_cb(callbacks, serverHeartbeatSucceeded)
            mongoc_apm_set_server_heartbeat_failed_cb(callbacks, serverHeartbeatFailed)
        }

        // we can pass the MongoClient as unretained because the callbacks are stored on clientHandle, so if the
        // callback is being executed, this pool and therefore its parent `MongoClient` must still be valid.
        switch self.state {
        case let .open(pool):
            mongoc_client_pool_set_apm_callbacks(pool, callbacks, Unmanaged.passUnretained(client).toOpaque())
        case .closed:
            fatalError("ConnectionPool was already closed")
        }
    }
}
