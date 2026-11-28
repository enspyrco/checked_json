/// A JSON object you only get by checking a value, which nothing can change:
/// [JsonObject], its typed readers, and the [JsonFieldException] they throw
/// naming the field; [MutableJsonObject] for building one; and
/// [decodeJsonRefusingDuplicateKeysAndUnsafeIntegers] for wire text of any
/// JSON kind.
library;

export 'src/decode_json.dart';
export 'src/json_object.dart';
