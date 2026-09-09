import Compression
import Foundation

enum ZipError: Error {
    case invalid
    case inflate
}

enum ZipExtractor {
    static func extract(data: Data, to destination: URL) throws {
        guard let eocd = findEOCD(in: data) else { throw ZipError.invalid }
        let count = Int(readUInt16(data, eocd + 10))
        var central = Int(readUInt32(data, eocd + 16))
        let fm = FileManager.default
        for _ in 0..<count {
            guard central + 46 <= data.count, readUInt32(data, central) == 0x02014b50 else {
                throw ZipError.invalid
            }
            let method = Int(readUInt16(data, central + 10))
            let compressedSize = Int(readUInt32(data, central + 20))
            let uncompressedSize = Int(readUInt32(data, central + 24))
            let nameLen = Int(readUInt16(data, central + 28))
            let extraLen = Int(readUInt16(data, central + 30))
            let commentLen = Int(readUInt16(data, central + 32))
            let localHeader = Int(readUInt32(data, central + 42))
            let nameStart = central + 46
            guard nameStart + nameLen <= data.count else { throw ZipError.invalid }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            let rel = name.replacingOccurrences(of: "\\", with: "/")
            if rel.hasPrefix("/") || rel.contains("..") {
                central = nameStart + nameLen + extraLen + commentLen
                continue
            }
            let isDir = rel.hasSuffix("/")
            let localNameLen = Int(readUInt16(data, localHeader + 26))
            let localExtra = Int(readUInt16(data, localHeader + 28))
            let dataStart = localHeader + 30 + localNameLen + localExtra
            let fileURL = destination.appendingPathComponent(rel)
            if isDir {
                try fm.createDirectory(at: fileURL, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let slice = data.subdata(in: dataStart..<(dataStart + compressedSize))
                let payload: Data
                if method == 0 {
                    payload = slice
                } else if method == 8 {
                    payload = try inflateRaw(slice, uncompressedSize: uncompressedSize)
                } else {
                    throw ZipError.invalid
                }
                try payload.write(to: fileURL, options: .atomic)
            }
            central = nameStart + nameLen + extraLen + commentLen
        }
    }

    private static func findEOCD(in data: Data) -> Int? {
        if data.count < 22 { return nil }
        let maxBack = min(data.count - 22, 65535)
        var i = data.count - 22
        let limit = data.count - 22 - maxBack
        while i >= limit {
            if readUInt32(data, i) == 0x06054b50 { return i }
            i -= 1
        }
        return nil
    }

    private static func inflateRaw(_ compressed: Data, uncompressedSize: Int) throws -> Data {
        var src = compressed
        let dstSize = max(uncompressedSize, 1)
        var dst = Data(count: dstSize)
        let result: Int = src.withUnsafeBytes { srcBuf in
            dst.withUnsafeMutableBytes { dstBuf in
                guard let srcPtr = srcBuf.baseAddress, let dstPtr = dstBuf.baseAddress else { return -1 }
                return compression_decode_buffer(
                    dstPtr.assumingMemoryBound(to: UInt8.self),
                    dstSize,
                    srcPtr.assumingMemoryBound(to: UInt8.self),
                    compressed.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        if result > 0 {
            return dst.prefix(result)
        }
        // ZIP deflate is raw; try wrapping as a zlib stream.
        var wrapped = Data([0x78, 0x01])
        wrapped.append(compressed)
        var dst2 = Data(count: dstSize)
        let result2: Int = wrapped.withUnsafeBytes { srcBuf in
            dst2.withUnsafeMutableBytes { dstBuf in
                guard let srcPtr = srcBuf.baseAddress, let dstPtr = dstBuf.baseAddress else { return -1 }
                return compression_decode_buffer(
                    dstPtr.assumingMemoryBound(to: UInt8.self),
                    dstSize,
                    srcPtr.assumingMemoryBound(to: UInt8.self),
                    wrapped.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard result2 > 0 else { throw ZipError.inflate }
        return dst2.prefix(result2)
    }
}

private func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
}

private func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[offset])
        | UInt32(data[offset + 1]) << 8
        | UInt32(data[offset + 2]) << 16
        | UInt32(data[offset + 3]) << 24
}
