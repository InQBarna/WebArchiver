//
//  ArchivingSession.swift
//  WebArchiver
//
//  Created by Ernesto Elsäßer on 15.06.19.
//  Copyright © 2019 Ernesto Elsäßer. All rights reserved.
//

import Foundation

class ArchivingSession {
    
    static var encoder: PropertyListEncoder = {
        let plistEncoder = PropertyListEncoder()
        plistEncoder.outputFormat = .binary
        return plistEncoder
    }()
    
    private var urlSession: URLSession
    private let completion: (ArchivingResult) -> ()
    private let cachePolicy: URLRequest.CachePolicy
    private var errors: [Error] = []
    private var pendingTaskCount: Int = 0
    
    init(session: URLSession, cachePolicy: URLRequest.CachePolicy, completion: @escaping (ArchivingResult) -> ()) {
        self.urlSession = session
        self.cachePolicy = cachePolicy
        self.completion = completion
    }
    
    func load(url: URL, fallback: WebArchive?, expand: @escaping (WebArchiveResource) throws -> WebArchive ) {
        pendingTaskCount = pendingTaskCount + 1

        var request = URLRequest(url: url)
        request.cachePolicy = cachePolicy
        let task = urlSession.dataTask(with: request) { (data, response, error) in
            self.pendingTaskCount = self.pendingTaskCount - 1
            
            var archive = fallback
            if let error = error {
                self.errors.append(ArchivingError.requestFailed(resource: url, error: error))
            } else if let data = data, let mimeType = (response as? HTTPURLResponse)?.mimeType {
                let resource = WebArchiveResource(url: url, data: data, mimeType: mimeType)
                do {
                    archive = try expand(resource)
                } catch {
                    self.errors.append(error)
                }
            } else {
                self.errors.append(ArchivingError.invalidResponse(resource: url))
            }
            
            self.finish(with: archive)
        }
        task.resume()
    }
    
    private func finish(with archive: WebArchive?) {
        
        guard self.pendingTaskCount == 0 else {
            return
        }
        
        var plistData: Data?
        if let archive = archive {
            do {
                plistData = try ArchivingSession.encoder.encode(archive)
            } catch {
                errors.append(error)
            }
        }
        
        let result = ArchivingResult(plistData: plistData, errors: errors)
        DispatchQueue.main.async {
            self.completion(result)
        }
    }
}
