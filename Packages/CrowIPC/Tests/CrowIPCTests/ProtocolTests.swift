import Foundation
import Testing
@testable import CrowIPC

// MARK: - JSONValue Encoding / Decoding

@Test func jsonValueStringRoundTrip() throws {
    let value = JSONValue.string("hello")
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded == value)
    #expect(decoded.stringValue == "hello")
}

@Test func jsonValueIntRoundTrip() throws {
    let value = JSONValue.int(42)
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded == value)
    #expect(decoded.intValue == 42)
}

@Test func jsonValueDoubleRoundTrip() throws {
    let value = JSONValue.double(3.14)
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded == value)
    #expect(decoded.doubleValue == 3.14)
}

@Test func jsonValueBoolRoundTrip() throws {
    let value = JSONValue.bool(true)
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded == value)
    #expect(decoded.boolValue == true)
}

@Test func jsonValueNullRoundTrip() throws {
    let value = JSONValue.null
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded == value)
}

@Test func jsonValueArrayRoundTrip() throws {
    let value = JSONValue.array([.string("a"), .int(1), .bool(false)])
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded == value)
    #expect(decoded.arrayValue?.count == 3)
}

@Test func jsonValueObjectRoundTrip() throws {
    let value = JSONValue.object(["key": .string("val"), "num": .int(7)])
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded == value)
    #expect(decoded.objectValue?["key"] == .string("val"))
}

@Test func jsonValueNestedStructure() throws {
    let value = JSONValue.object([
        "items": .array([.object(["id": .int(1), "name": .string("test")])]),
        "count": .int(1),
    ])
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded == value)
}

// MARK: - Accessor Returns Nil for Wrong Type

@Test func jsonValueAccessorsMismatch() {
    let str = JSONValue.string("hello")
    #expect(str.intValue == nil)
    #expect(str.doubleValue == nil)
    #expect(str.boolValue == nil)
    #expect(str.arrayValue == nil)
    #expect(str.objectValue == nil)

    let num = JSONValue.int(42)
    #expect(num.stringValue == nil)
    #expect(num.doubleValue == nil)
    #expect(num.boolValue == nil)
}

// MARK: - Number Type Disambiguation

@Test func jsonValueIntDecodesAsInt() throws {
    let data = "42".data(using: .utf8)!
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded == .int(42))
}

@Test func jsonValueFractionalDecodesAsDouble() throws {
    let data = "42.5".data(using: .utf8)!
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(decoded == .double(42.5))
}

// MARK: - JSONRPCRequest

@Test func requestEncodesCorrectly() throws {
    let request = JSONRPCRequest(id: 1, method: "test", params: ["key": .string("val")])
    let data = try JSONEncoder().encode(request)
    let json = try JSONDecoder().decode([String: JSONValue].self, from: data)

    #expect(json["jsonrpc"] == .string("2.0"))
    #expect(json["id"] == .int(1))
    #expect(json["method"] == .string("test"))
}

@Test func requestWithNilParams() throws {
    let request = JSONRPCRequest(id: 1, method: "test")
    let data = try JSONEncoder().encode(request)
    let str = String(data: data, encoding: .utf8)!
    #expect(!str.contains("params"))
}

// MARK: - JSONRPCResponse Factories

@Test func responseSuccessFactory() {
    let response = JSONRPCResponse.success(id: 5, result: ["ok": .bool(true)])
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == 5)
    #expect(response.result?["ok"] == .bool(true))
    #expect(response.error == nil)
}

@Test func responseErrorFactory() {
    let response = JSONRPCResponse.error(id: 3, code: -32600, message: "bad request")
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == 3)
    #expect(response.result == nil)
    #expect(response.error?.code == -32600)
    #expect(response.error?.message == "bad request")
}

// MARK: - Hashable Conformance

@Test func jsonValueHashable() {
    let set: Set<JSONValue> = [.string("a"), .string("b"), .string("a"), .int(1)]
    #expect(set.count == 3)
}

// MARK: - Error Codes

@Test func rpcErrorCodeValues() {
    #expect(RPCErrorCode.parseError == -32700)
    #expect(RPCErrorCode.invalidRequest == -32600)
    #expect(RPCErrorCode.methodNotFound == -32601)
    #expect(RPCErrorCode.invalidParams == -32602)
    #expect(RPCErrorCode.internalError == -32603)
    #expect(RPCErrorCode.applicationError == -32000)
}
