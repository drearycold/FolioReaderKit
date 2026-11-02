import Foundation
import ReadiumGCDWebServer
import ReadiumZIPFoundation

/// A single byte range, expressed as half-open ZIP offsets. Unsupported Range syntax is ignored.
enum EpubByteRange: Equatable {
    case full
    case partial(Range<UInt64>)
    case unsatisfiable

    static func parse(_ header: String?, length: UInt64) -> EpubByteRange {
        guard let header = header, header.hasPrefix("bytes=") else { return .full }
        let pieces = header.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 2 else { return .full }
        func number(_ value: Substring) -> UInt64? {
            guard !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
            return UInt64(value)
        }
        if pieces[0].isEmpty {
            guard let suffix = number(pieces[1]) else { return .full }
            guard suffix > 0, length > 0 else { return .unsatisfiable }
            return .partial((length - min(length, suffix))..<length)
        }
        guard let start = number(pieces[0]) else { return .full }
        if pieces[1].isEmpty {
            return start < length ? .partial(start..<length) : .unsatisfiable
        }
        guard let end = number(pieces[1]), end >= start else { return .full }
        guard start < length else { return .unsatisfiable }
        return .partial(start..<(min(end, length - 1) + 1))
    }
}

/// One queued chunk at most. A producer suspends until its queued chunk is consumed; no bytes drop.
actor ZipEntryChannel {
    private var pending: (Data, CheckedContinuation<Void, Error>)?
    private var reader: CheckedContinuation<Data?, Error>?
    private var finished = false
    private var failure: Error?

    var bufferedChunkCount: Int { pending == nil ? 0 : 1 }

    func send(_ data: Data) async throws {
        try Task.checkCancellation()
        guard !finished else { throw failure ?? CancellationError() }
        guard !data.isEmpty else { return }
        if let reader = reader {
            self.reader = nil
            reader.resume(returning: data)
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            precondition(pending == nil)
            pending = (data, continuation)
        }
    }

    func next() async throws -> Data? {
        if let (data, producer) = pending {
            pending = nil
            producer.resume()
            return data
        }
        if let failure = failure { throw failure }
        if finished { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            precondition(reader == nil)
            reader = continuation
        }
    }

    func finish(error: Error? = nil) {
        guard !finished else { return }
        finished = true
        failure = error
        if let (_, producer) = pending {
            pending = nil
            producer.resume(throwing: error ?? CancellationError())
        }
        if let reader = reader {
            self.reader = nil
            if let error = error { reader.resume(throwing: error) }
            else { reader.resume(returning: nil) }
        }
    }
}

/// Unlike ZIPFoundation's Deflate range reader, this sees every inflated chunk, including the
/// discarded prefix, so cancellation is observed before the first requested byte is reached.
private actor ZipEntryRangeConsumer {
    struct EndOfRange: Error {}
    private let range: Range<UInt64>
    private let channel: ZipEntryChannel
    private var offset: UInt64 = 0

    init(range: Range<UInt64>, channel: ZipEntryChannel) {
        self.range = range
        self.channel = channel
    }

    func consume(_ data: Data) async throws {
        try Task.checkCancellation()
        let start = offset
        offset += UInt64(data.count)
        let lower = max(start, range.lowerBound)
        let upper = min(offset, range.upperBound)
        if lower < upper {
            let from = data.index(data.startIndex, offsetBy: Int(lower - start))
            let to = data.index(data.startIndex, offsetBy: Int(upper - start))
            try await channel.send(Data(data[from..<to]))
        }
        if offset >= range.upperBound { throw EndOfRange() }
    }
}

/// Owns extraction independently of the HTTP response so closing it releases suspended consumers.
final class ZipEntryStream {
    let channel = ZipEntryChannel()
    private let producer: Task<Void, Never>

    init(archive: Archive, entry: Entry, range: Range<UInt64>?) {
        let channel = self.channel
        producer = Task {
            do {
                try Task.checkCancellation()
                if let range = range, entry.isCompressed {
                    let consumer = ZipEntryRangeConsumer(range: range, channel: channel)
                    do {
                        _ = try await archive.extract(entry, bufferSize: 64 * 1024, skipCRC32: true) { data in
                            try await consumer.consume(data)
                        }
                    } catch is ZipEntryRangeConsumer.EndOfRange {
                        // The requested bytes are complete; don't inflate the rest of the entry.
                    }
                } else if let range = range {
                    try await archive.extractRange(range, of: entry, bufferSize: 64 * 1024) { data in
                        try await channel.send(data)
                    }
                } else {
                    let checksum = try await archive.extract(entry, bufferSize: 64 * 1024) { data in
                        try await channel.send(data)
                    }
                    guard checksum == entry.checksum else {
                        throw NSError(domain: "FolioReaderKit.ZIP", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "ZIP entry checksum mismatch"])
                    }
                }
                await channel.finish()
            } catch {
                await channel.finish(error: error)
            }
        }
    }

    func cancel() {
        producer.cancel()
        let channel = self.channel
        Task { await channel.finish(error: CancellationError()) }
    }

    func waitForCompletion() async { await producer.value }
    deinit { cancel() }
}

final class ZipEntryResponse: ReadiumGCDWebServerStreamedResponse {
    let stream: ZipEntryStream

    init(archive: Archive, entry: Entry, contentType: String, range: Range<UInt64>?) {
        stream = ZipEntryStream(archive: archive, entry: entry, range: range)
        let channel = stream.channel
        super.init(contentType: contentType, asyncStreamBlock: { completion in
            Task {
                do { completion(try await channel.next() ?? Data(), nil) }
                catch { completion(nil, error) }
            }
        })
        contentLength = UInt(range.map { $0.upperBound - $0.lowerBound } ?? entry.uncompressedSize)
        setValue("bytes", forAdditionalHeader: "Accept-Ranges")
        if let range = range {
            statusCode = 206
            setValue("bytes \(range.lowerBound)-\(range.upperBound - 1)/\(entry.uncompressedSize)", forAdditionalHeader: "Content-Range")
        }
    }

    override func close() {
        stream.cancel()
        super.close()
    }
}
