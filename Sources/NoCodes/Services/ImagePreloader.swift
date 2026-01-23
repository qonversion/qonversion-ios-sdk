//
//  ImagePreloader.swift
//  NoCodes
//
//  Created on 22.01.2026.
//  Copyright © 2026 Qonversion Inc. All rights reserved.
//

import Foundation

#if os(iOS)

final class ImagePreloader: ImagePreloaderInterface {
  
  private let urlSession: URLSession
  private let logger: LoggerWrapper
  
  /// Maximum time to wait for all images to load
  private let timeout: TimeInterval
  
  /// Maximum number of concurrent image downloads
  private let maxConcurrentDownloads: Int
  
  init(
    urlSession: URLSession = .shared,
    logger: LoggerWrapper,
    timeout: TimeInterval = 10.0,
    maxConcurrentDownloads: Int = 5
  ) {
    self.urlSession = urlSession
    self.logger = logger
    self.timeout = timeout
    self.maxConcurrentDownloads = maxConcurrentDownloads
  }
  
  // MARK: - ImagePreloaderInterface
  
  func preloadImages(in html: String) async -> String {
    let imageUrls = extractImageUrls(from: html)
    
    guard !imageUrls.isEmpty else {
      logger.info("No external images found in HTML")
      return html
    }
    
    logger.info("Found \(imageUrls.count) images to preload")
    
    // Download images with timeout
    let replacements = await downloadImagesWithTimeout(urls: imageUrls)
    
    // Replace URLs with base64 data URIs
    let modifiedHtml = replaceUrls(in: html, with: replacements)
    
    logger.info("Successfully preloaded \(replacements.count) of \(imageUrls.count) images")
    
    return modifiedHtml
  }
  
  // MARK: - Private Methods
  
  /// Extracts image URLs from HTML content.
  /// Handles both `<img src="...">` tags and `background-image: url(...)` CSS.
  private func extractImageUrls(from html: String) -> Set<String> {
    var urls = Set<String>()
    
    // Pattern for <img src="..."> or <img src='...'>
    let imgPattern = #"<img[^>]+src\s*=\s*[\"']([^\"']+)[\"']"#
    
    // Pattern for background-image: url(...) with optional quotes
    let bgPattern = #"background-image\s*:\s*url\s*\(\s*[\"']?([^\"')]+)[\"']?\s*\)"#
    
    // Extract from img tags
    urls.formUnion(extractMatches(from: html, pattern: imgPattern))
    
    // Extract from background-image
    urls.formUnion(extractMatches(from: html, pattern: bgPattern))
    
    // Filter only valid HTTP(S) URLs (skip data URIs, relative paths, etc.)
    let httpUrls = urls.filter { url in
      url.hasPrefix("http://") || url.hasPrefix("https://")
    }
    
    return httpUrls
  }
  
  /// Extracts regex matches from text.
  private func extractMatches(from text: String, pattern: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
      return []
    }
    
    let range = NSRange(text.startIndex..., in: text)
    let matches = regex.matches(in: text, options: [], range: range)
    
    return matches.compactMap { match -> String? in
      guard match.numberOfRanges > 1,
            let urlRange = Range(match.range(at: 1), in: text) else {
        return nil
      }
      return String(text[urlRange])
    }
  }
  
  /// Downloads images with timeout, returns dictionary of URL -> base64 data URI.
  private func downloadImagesWithTimeout(urls: Set<String>) async -> [String: String] {
    await withTaskGroup(of: (String, String?).self) { group in
      var replacements: [String: String] = [:]
      var pendingCount = 0
      var urlsIterator = urls.makeIterator()
      
      // Start initial batch of downloads
      for _ in 0..<min(maxConcurrentDownloads, urls.count) {
        if let url = urlsIterator.next() {
          pendingCount += 1
          group.addTask {
            await self.downloadAndConvert(url: url)
          }
        }
      }
      
      // Process results and add more tasks
      for await (url, dataUri) in group {
        pendingCount -= 1
        
        if let dataUri = dataUri {
          replacements[url] = dataUri
        }
        
        // Add next URL if available
        if let nextUrl = urlsIterator.next() {
          pendingCount += 1
          group.addTask {
            await self.downloadAndConvert(url: nextUrl)
          }
        }
      }
      
      return replacements
    }
  }
  
  /// Downloads a single image and converts it to base64 data URI.
  private func downloadAndConvert(url urlString: String) async -> (String, String?) {
    guard let url = URL(string: urlString) else {
      logger.warning("Invalid URL: \(urlString)")
      return (urlString, nil)
    }
    
    do {
      let (data, response) = try await urlSession.data(from: url)
      
      guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode) else {
        logger.warning("Failed to download image: \(urlString)")
        return (urlString, nil)
      }
      
      let mimeType = detectMimeType(from: response, data: data, url: url)
      let base64 = data.base64EncodedString()
      let dataUri = "data:\(mimeType);base64,\(base64)"
      
      return (urlString, dataUri)
    } catch {
      logger.warning("Error downloading image \(urlString): \(error.localizedDescription)")
      return (urlString, nil)
    }
  }
  
  /// Detects MIME type from response or file extension.
  private func detectMimeType(from response: URLResponse, data: Data, url: URL) -> String {
    // Try to get MIME type from response
    if let mimeType = response.mimeType, !mimeType.isEmpty {
      return mimeType
    }
    
    // Fallback: detect from file extension
    let ext = url.pathExtension.lowercased()
    switch ext {
    case "png":
      return "image/png"
    case "jpg", "jpeg":
      return "image/jpeg"
    case "gif":
      return "image/gif"
    case "webp":
      return "image/webp"
    case "svg":
      return "image/svg+xml"
    case "ico":
      return "image/x-icon"
    case "bmp":
      return "image/bmp"
    default:
      // Try to detect from data magic bytes
      return detectMimeTypeFromData(data) ?? "image/png"
    }
  }
  
  /// Detects MIME type from data magic bytes.
  private func detectMimeTypeFromData(_ data: Data) -> String? {
    guard data.count >= 4 else { return nil }
    
    let bytes = [UInt8](data.prefix(12))
    
    // PNG: 89 50 4E 47
    if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
      return "image/png"
    }
    
    // JPEG: FF D8 FF
    if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
      return "image/jpeg"
    }
    
    // GIF: GIF87a or GIF89a
    if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) {
      return "image/gif"
    }
    
    // WebP: RIFF....WEBP
    if bytes.count >= 12 &&
       bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) &&
       bytes[8...11] == [0x57, 0x45, 0x42, 0x50] {
      return "image/webp"
    }
    
    return nil
  }
  
  /// Replaces image URLs in HTML with base64 data URIs.
  /// Uses simple string replacement instead of regex to avoid issues with special characters in base64.
  private func replaceUrls(in html: String, with replacements: [String: String]) -> String {
    var result = html
    
    for (originalUrl, dataUri) in replacements {
      // Simple string replacement - much safer for base64 data URIs
      // which may contain special regex characters like +, /, $
      result = result.replacingOccurrences(of: originalUrl, with: dataUri)
    }
    
    return result
  }
  
}

#endif
