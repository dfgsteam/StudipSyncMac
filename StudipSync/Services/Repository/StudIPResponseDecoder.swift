import Foundation

struct StudIPResponseDecoder {
    func parseCollection<Model: Decodable>(
        from data: Data,
        fallbackCollectionKeys: [String]
    ) throws -> [Model] {
        if let wrapped: JSONAPIListResponse<Model> = decodeIfPossible(data) {
            return wrapped.data
        }
        if let plain: [Model] = decodeIfPossible(data) {
            return plain
        }

        if let extracted = try extractArrayFromUnknownPayload(data, candidateKeys: fallbackCollectionKeys) {
            return try decodeArrayElements(extracted, as: Model.self)
        }

        throw StudIPRepositoryError.invalidPayloadPreview(previewString(from: data))
    }

    func parseEntity<Model: Decodable>(
        from data: Data,
        fallbackObjectKeys: [String]
    ) throws -> Model {
        if let wrapped: JSONAPISingleResponse<Model> = decodeIfPossible(data) {
            return wrapped.data
        }
        if let plain: Model = decodeIfPossible(data) {
            return plain
        }

        let json = try JSONSerialization.jsonObject(with: data)

        if let dictionary = json as? [String: Any] {
            for key in fallbackObjectKeys {
                if let nested = dictionary[key] as? [String: Any],
                   let decoded: Model = decodeJSONObject(nested) {
                    return decoded
                }
            }
        }

        if let array = try extractArrayFromUnknownPayload(data, candidateKeys: fallbackObjectKeys),
           let first = array.first,
           let decoded: Model = decodeJSONObject(first) {
            return decoded
        }

        throw StudIPRepositoryError.invalidPayloadPreview(previewString(from: data))
    }

    private func decodeIfPossible<T: Decodable>(_ data: Data) -> T? {
        try? JSONDecoder().decode(T.self, from: data)
    }

    private func decodeArrayElements<T: Decodable>(_ elements: [Any], as type: T.Type) throws -> [T] {
        var result: [T] = []

        for element in elements {
            if let decoded: T = decodeJSONObject(element) {
                result.append(decoded)
                continue
            }

            if let dictionary = element as? [String: Any],
               let nestedObject = dictionary.values.first,
               let decodedNested: T = decodeJSONObject(nestedObject) {
                result.append(decodedNested)
                continue
            }

            if let stringElement = element as? String,
               let stringData = stringElement.data(using: .utf8),
               let decodedString: T = decodeIfPossible(stringData) {
                result.append(decodedString)
            }
        }

        if result.isEmpty {
            let samplePreview = String(describing: elements.first ?? "<leer>")
            throw StudIPRepositoryError.invalidPayloadPreview(
                "Array vorhanden, aber Elemente nicht dekodierbar. Erstes Element: \(samplePreview.prefix(180))"
            )
        }

        return result
    }

    private func decodeJSONObject<T: Decodable>(_ object: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(object) else {
            return nil
        }
        guard let itemData = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return decodeIfPossible(itemData)
    }

    private func extractArrayFromUnknownPayload(_ data: Data, candidateKeys: [String]) throws -> [Any]? {
        let json = try JSONSerialization.jsonObject(with: data)

        if let array = json as? [Any] {
            return array
        }

        guard let dictionary = json as? [String: Any] else {
            return nil
        }

        for key in candidateKeys {
            if let array = dictionary[key] as? [Any] {
                return array
            }
            if let objectMap = dictionary[key] as? [String: Any] {
                return valuesWithInjectedIDs(from: objectMap)
            }
        }

        for value in dictionary.values {
            if let nested = value as? [String: Any] {
                for key in candidateKeys {
                    if let array = nested[key] as? [Any] {
                        return array
                    }
                    if let objectMap = nested[key] as? [String: Any] {
                        return valuesWithInjectedIDs(from: objectMap)
                    }
                }
            }
        }

        return nil
    }

    private func previewString(from data: Data) -> String {
        let text = String(data: data, encoding: .utf8) ?? "<nicht-UTF8 payload>"
        let compact = text.replacingOccurrences(of: "\n", with: " ")
        return String(compact.prefix(240))
    }

    private func valuesWithInjectedIDs(from objectMap: [String: Any]) -> [Any] {
        objectMap.map { key, value in
            guard var dictionary = value as? [String: Any] else {
                return value
            }
            if dictionary["id"] == nil {
                dictionary["id"] = key
            }
            return dictionary
        }
    }
}
