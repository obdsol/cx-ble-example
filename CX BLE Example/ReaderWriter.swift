//
//  ReaderWriter.swift
//  CX BLE Example
//
//  Created by Robby Madruga on 2/6/21.
//

import Foundation
import SwiftCoroutine



protocol ReaderWriter {
    var scope: CoScope { get set }
    func readChar() -> CoFuture<Character>
    func writeString(data: String) -> CoFuture<()>
    func flush(timeout: DispatchTimeInterval) -> CoFuture<()>
}



extension ReaderWriter {
    func sendCommand(_ command: String) -> CoFuture<()> {
        writeString(data: "\(command)\r")
    }
    
    func sendCommandWithResponse(_ command: String, timeout: DispatchTimeInterval = .seconds(1)) -> CoFuture<String> {
        DispatchQueue.global().coroutineFuture() {
            try sendCommand(command).await()
            var response = try readUntil(terminator: ">", timeout: timeout).await()
            if response.hasPrefix(command) {
                response = String(response.dropFirst(command.count))
            }
            response = String(response.dropLast(3))
            return response
        }.added(to: scope)
    }
    
    func readUntil(terminator: Character, timeout: DispatchTimeInterval) -> CoFuture<String> {
        let endTime = DispatchTime.now() + timeout
        return DispatchQueue.global().coroutineFuture() {
            var output = String()
            
            while true {
                do {
                    let char = try readChar().await(timeout: DispatchTime.now().distance(to: endTime))
                    output.append(char)
                    if char == terminator { break }
                } catch CoFutureError.timeout { break }
            }
            
            return output
        }.added(to: scope)
    }
}
