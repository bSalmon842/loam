/*
Project: Loam
File: json.jai
Author: Brock Salmon
Created: 03OCT2025
*/

// Loam JSON parser
// TODO: Free value names

JSON_ValueType :: enum {
    Invalid;
    
    Object;
    Array;

    Number;
    String;
    Boolean;
    
    Null;
}

JSON_ErrorType :: enum u32 {
    Success;

    FailedToOpenRoot;    // Did we not find a '{' or '[' when starting the file
    FailedToCloseValue;  // Did we hit the end of the file or the next value without closing the all relevant scopes ( using '}', ']', or ',')
    DataAfterClose;      // Found something other than whitespace after the root close
    ValueTypeUndefined;  // Entered json_parse_this without the basic value type being setup

    MalformedKey;        // Didn't find a correctly formed name for a value inside an object (usually missing a " )
    NoValueSeparator;    // Didn't find a ':' separator when expected
    InvalidValue;        // Malformed value data
    ExtraComma;          // Data contains a comma between last element and closer
    LeadingZeroes;       // Number value leading with zero
    HexNumber;           // Hex representations are not allowed in JSON
    InvalidEscape;       // Unsupported Escape sequence used
    InvalidWhitespace;   // Raw tab used instead of an escape character in the JSON file
}

JSON_Value :: struct {
    type : JSON_ValueType;
    name : string;
    parent : *JSON_Value;
    
    union {
	values : [..] *JSON_Value;

	union {
	    value_string  : string;
	    value_bool    : bool;
	    value_float   : float64;
	    value_null    : *void;
	}
    }
}

json_get :: (value : *JSON_Value, $returnType : Type) -> returnType, bool #modify {
    return returnType == float64 || returnType == string || returnType == bool || returnType == *void;
}{
    if !value {
	if #compile_time {
	    print("json_get failed due to invalid value!\n");
	} else {
	    log(.ERROR, "json_get failed due to invalid value!");
	}
	err : returnType;
	return err, false;
    }

    if value.type == .Array || value.type == .Object {
	if #compile_time {
	    print("json_get failed due to invalid get type: %\n", value.type);
	} else {
	    log(.ERROR, tprint("json_get failed due to invalid get type: %", value.type));
	}
	err : returnType;
	return err, false;
    }

    #if returnType == string {
	return value.value_string, true;
    } else #if returnType == float64 {
	return value.value_float, true;
    } else #if returnType == bool {
	return value.value_bool, true;
    } else #if returnType == *void {
	return value.value_null, true;
    }
    
    err : returnType;
    return err, false;
}

json_eat_whitespace :: (s : string) -> string #expand {
    return trim_left(s, JSON_WHITESPACE);
}

// NOTE: We do not free inside json_build_tree, free should be done on error where json_build_tree is used
json_build_tree :: (jsonData : string, debugName : string) -> *JSON_Value, JSON_ErrorType {
    root := New(JSON_Value);
    root.name = "root";
    
    parseString := json_eat_whitespace(jsonData);
    if parseString.data.* == #char "{" {
	root.type = .Object;	
    } else if parseString.data.* == #char "[" {
	root.type = .Array;
    } else {
	json_log_error(.FailedToOpenRoot, debugName, to_string(parseString.data, 1));
	return root, .FailedToOpenRoot;
    }

    parseString=, error:= json_parse_this(root, parseString, debugName);
    if error then return root, error;

    parseString = json_eat_whitespace(parseString);
    if parseString.count > 0 {
	json_log_error(.DataAfterClose, debugName, "");
	return root, .DataAfterClose;
    }
    // TODO: If there is another object (we don't need to error for that, just log a warning and ignore it)

    return root, .Success;
}

json_free_value :: (value : *JSON_Value) {
    if value.name.data then free(value.name.data);
    if value.type == .Object || value.type == .Array {
	for value.values {
	    json_free_value(it);
	}
    } else if value.type == .String {
	if value.value_string.data then free(value.value_string.data);
    }

    value.* = .{};
    free(value);
}

json_parse_this :: (value : *JSON_Value, json : string, debugName : string) -> string, JSON_ErrorType {
    if value.type == .Invalid {
	json_log_error(.ValueTypeUndefined, debugName, value.name);
	return json, .ValueTypeUndefined;
    }
    
    thisString := json;
    if value.type == .Object || value.type == .Array then advance(*thisString);
    
    if value.type == {
	case .Object; {
	    thisString = json_eat_whitespace(thisString);
	    if thisString.data.* == #char "}" {
		// Empty Object
		advance(*thisString);
		return thisString, .Success;
	    }
	    
	    findingValues := true;
	    while findingValues {
		thisString = json_eat_whitespace(thisString);

		if thisString.count == 0 {
		    json_log_error(.FailedToCloseValue, debugName, "");
		    return thisString, .FailedToCloseValue;
		}

		if thisString.data.* == #char "}" {
		    json_log_error(.ExtraComma, debugName, "");
		    return thisString, .ExtraComma;
		}

		internalValue := New(JSON_Value);
		array_add(*value.values, internalValue);
		internalValue.parent = value;
		
		if thisString.data.* != #char "\"" {
		    json_log_error(.MalformedKey, debugName, "beginning");
		    return thisString, .MalformedKey;
		}
		
		advance(*thisString);

		keyString, error := process_string_key_or_value(thisString, debugName);
		if error then return thisString, error;
		
		internalValue.name = copy_string(keyString);

		advance(*thisString, keyString.count + 1);
		thisString = json_eat_whitespace(thisString);

		if thisString.data.* != #char ":" {
		    json_log_error(.NoValueSeparator, debugName, to_string(thisString.data, 1));
		    return thisString, .NoValueSeparator;
		}

		advance(*thisString);
		thisString = json_eat_whitespace(thisString);

		if is_number_char(thisString.data.*) {
		    internalValue.type = .Number;
		} else if thisString.data.* == #char "\"" {
		    internalValue.type = .String;
		} else if thisString.data.* == #char "{" {
		    internalValue.type = .Object;
		} else if thisString.data.* == #char "[" {
		    internalValue.type = .Array;
		} else if begins_with(thisString, "null") {
		    internalValue.type = .Null;
		} else if begins_with(thisString, "true") || begins_with(thisString, "false") {
		    internalValue.type = .Boolean;
		} else {
		    closeIndex := find_index_of_any_from_left(thisString, ",}]");
		    if closeIndex == -1 {
			json_log_error(.FailedToCloseValue, debugName, "");
			return thisString, .FailedToCloseValue;
		    }
		    
		    errorString := string.{ closeIndex, thisString.data };
		    json_log_error(.InvalidValue, debugName, errorString);
		    return thisString, .InvalidValue;
		}
		
		thisString, error = json_parse_this(internalValue, thisString, debugName);
		if error then return thisString, error; // Error will already be logged inside the recursive json_parse_this
		
		thisString = json_eat_whitespace(thisString);
		
		if thisString.data.* == #char "," {
		    advance(*thisString);
		    // Continue to the next value
		} else if thisString.data.* == #char "}" {
		    advance(*thisString);
		    findingValues = false;
		} else {
		    json_log_error(.FailedToCloseValue, debugName, thisString);
		    return thisString, .FailedToCloseValue;
		}
	    }
	}

	case .Array; {
	    thisString = json_eat_whitespace(thisString);
	    if thisString.data.* == #char "]" {
		// Empty Array
		advance(*thisString);
		return thisString, .Success;
	    }
	    
	    findingValues := true;
	    valueIndex := 0;
	    while findingValues {
		thisString = json_eat_whitespace(thisString);

		if thisString.data.* == #char "]" || thisString.data.* == #char "," {
		    json_log_error(.ExtraComma, debugName, "");
		    return thisString, .ExtraComma;
		}
		
		internalValue := New(JSON_Value);
		array_add(*value.values, internalValue);
		internalValue.parent = value;
		internalValue.name = sprint("array_%_elem_%", value.name, valueIndex);
		
		if is_number_char(thisString.data.*) {
		    internalValue.type = .Number;
		} else if thisString.data.* == #char "\"" {
		    internalValue.type = .String;
		} else if thisString.data.* == #char "{" {
		    internalValue.type = .Object;
		} else if thisString.data.* == #char "[" {
		    internalValue.type = .Array;
		} else if begins_with(thisString, "null") {
		    internalValue.type = .Null;
		} else if begins_with(thisString, "true") || begins_with(thisString, "false") {
		    internalValue.type = .Boolean;
		} else {
		    closeIndex := find_index_of_any_from_left(thisString, ",}]");
		    if closeIndex == -1 {
			json_log_error(.FailedToCloseValue, debugName, "");
			return thisString, .FailedToCloseValue;
		    }
		    
		    errorString := string.{ closeIndex, thisString.data };
		    json_log_error(.InvalidValue, debugName, errorString);
		    return thisString, .InvalidValue;
		}
		
		thisString=, error:= json_parse_this(internalValue, thisString, debugName);
		if error then return thisString, error; // Error will already be logged inside the recursive json_parse_this

		if thisString.count == 0 {
		    json_log_error(.FailedToCloseValue, debugName, "");
		    return thisString, .FailedToCloseValue;
		}
		
		thisString = json_eat_whitespace(thisString);
		
		if thisString.data.* == #char "," {
		    advance(*thisString);
		    // Continue to the next value
		} else if thisString.data.* == #char "]" {
		    advance(*thisString);
		    findingValues = false;
		} else {
		    json_log_error(.FailedToCloseValue, debugName, "");
		    return thisString, .FailedToCloseValue;
		}

		valueIndex += 1;
	    }
	}

	case .Number; {
	    closeIndex := find_index_of_any_from_left(thisString, ",}]");
	    if closeIndex == -1 {
		json_log_error(.FailedToCloseValue, debugName, "");
		return thisString, .FailedToCloseValue;
	    }

	    numberString := string.{ closeIndex, thisString.data };
	    numberString = trim(numberString, JSON_WHITESPACE);
    	    to_lower_in_place(numberString);
	    originalNumberString := numberString;
	    
	    for numberString {
		if !is_number_char(it) {
		    // Handle hexadecimal
		    if numberString.count >= 3 && begins_with(numberString, "0x") {
			json_log_error(.HexNumber, debugName, numberString);
			return thisString, .HexNumber;
		    }
		    
		    json_log_error(.InvalidValue, debugName, numberString);
		    return thisString, .InvalidValue;
		}
	    }
	    
	    if numberString.data.* == #char "-" {
		advance(*numberString);
	    }
	    
	    // Handle leading zeroes
	    if numberString.count > 1 && numberString.data.* == #char "0" && !contains_any_character(numberString, "e.") {
		json_log_error(.LeadingZeroes, debugName, numberString);
		return thisString, .LeadingZeroes;
	    }

	    if contains_any_character(numberString, "e") {
		numberParts := split(numberString, "e");
		if numberParts.count != 2 || numberParts[0].count == 0 || numberParts[1].count == 0 {
		    json_log_error(.InvalidValue, debugName, numberString);
		    return thisString, .InvalidValue;
		}

		// Check second part isn't a float
		if contains(numberParts[1], ".") {
		    json_log_error(.InvalidValue, debugName, numberString);
		    return thisString, .InvalidValue;
		}

		foundNumber := false;
		for numberParts[1] {
		    if it_index != 0 && contains("+-", it) {
			json_log_error(.InvalidValue, debugName, numberString);
			return thisString, .InvalidValue;
		    }
		    
		    if it >= #char "0" && it <= #char "9" {
			foundNumber = true;
		    }
		}

		if !foundNumber {
		    json_log_error(.InvalidValue, debugName, numberString);
		    return thisString, .InvalidValue;
		}
	    }

	    number, converted := string_to_float64(originalNumberString);
	    if !converted {
		json_log_error(.InvalidValue, debugName, originalNumberString);
		return thisString, .InvalidValue;
	    }

	    value.value_float = number;
	    advance(*thisString, originalNumberString.count);
	}
	
	case .String; {
	    advance(*thisString);

	    valueString, error := process_string_key_or_value(thisString, debugName);
	    if error then return thisString, error;
	    
	    value.value_string = copy_string(valueString);
	    advance(*thisString, valueString.count + 1);
	}
	
	case .Boolean; {
	    // NOTE: We check for true or false before this point, so this is pretty simple to parse
	    boolValue := begins_with(thisString, "true");
	    value.value_bool = boolValue;
	    advance(*thisString, ifx boolValue then 4 else 5);
	}
	
	case .Null; {
	    // NOTE: We check for null before this point, so this is pretty simple to parse
	    value.value_null = null;
	    advance(*thisString, 4);
	}
    }
    
    return thisString, .Success;
}

json_log_error :: (error : JSON_ErrorType, debugName : string, errorInfo : string) {
    if error == .Success then return; // We don't need to log successes;

    baseErrorString := tprint("JSON Error %: Failed to parse JSON data for \"%\"", error, debugName);
    extraErrorString := "MALFORMED ERROR";
    if #complete error == {
	case .Success;

	case .FailedToOpenRoot;   extraErrorString = tprint("expected the opening of an object or array for root, instead found %", errorInfo);
	case .FailedToCloseValue; extraErrorString = tprint("did not find a close to the current value %", errorInfo);
	case .DataAfterClose;     extraErrorString = "non-whitespace found after the close of the root object/array";
	case .ValueTypeUndefined; extraErrorString = tprint("attempted to parse a value (\"%\") without a defined type", errorInfo);
	case .MalformedKey;       extraErrorString = tprint("expected to parse a value name but didn't find a % quotation", errorInfo);
	case .NoValueSeparator;   extraErrorString = tprint("expected a value separator \":\", instead found %", errorInfo);
	case .InvalidValue;       extraErrorString = tprint("found an invalid value \"%\"", errorInfo);
	case .ExtraComma;         extraErrorString = "found an unexpected comma, check for: commas after last elements in objects/arrays, double commas, or missing values in objects/arrays";
	case .LeadingZeroes;      extraErrorString = tprint("number values cannot have leading zeroes: \"%\"", errorInfo);
	case .HexNumber;          extraErrorString = tprint("number values cannot be in hexadecimal format: \"%\"", errorInfo);
	case .InvalidEscape;      extraErrorString = tprint("invalid escape sequence used: \"%\"", errorInfo);
	case .InvalidWhitespace;  extraErrorString = tprint("invalid whitespace in value: \"%\"", errorInfo);
    }
 
    fullError := tprint("%, %", baseErrorString, extraErrorString);
    
    print_color("%\n", fullError, color = .HI_WHITE);
}

#scope_file
JSON_NUMBER_CHARS :: "0123456789.-+eE";
JSON_VALID_ESCAPES :: "\\/\"bfnrtu";
JSON_WHITESPACE :: " \t\n\r";

is_number_char :: (char : u8) -> bool {
    return contains(JSON_NUMBER_CHARS, char);
}

is_escape_char :: (char : u8) -> bool {
    return contains(JSON_VALID_ESCAPES, char);
}

process_string_key_or_value :: (thisString : string, debugName : string) -> string, JSON_ErrorType {
    valueStringLength := 0;
    tempString := copy_string(thisString,, temp);
    parsingStringValue := true;
    while parsingStringValue {
	if tempString.count == 0 {
	    json_log_error(.FailedToCloseValue, debugName, "");
	    return thisString, .FailedToCloseValue;
	}
	
	if tempString.data.* == #char "\"" {
	    parsingStringValue = true;
	    break;
	}

	if tempString.data.* == #char "\t" || tempString.data.* == #char "\n" {
	    json_log_error(.InvalidWhitespace, debugName, tempString);
	    return thisString, .InvalidWhitespace;
	}
	
	if tempString.data.* == #char "\\" {
	    advance(*tempString);
    	    valueStringLength += 1;

	    if !is_escape_char(tempString.data.*) {
		json_log_error(.InvalidEscape, debugName, tempString);
		return thisString, .InvalidEscape;
	    } else if tempString.data.* == #char "u" {
		if tempString.count < 5 {
		    // TODO: Check if valid hex
		    json_log_error(.InvalidEscape, debugName, tempString);
		    return thisString, .InvalidEscape;
		}
	    }
	}
	
	advance(*tempString);
	valueStringLength += 1;
    }
    
    return .{ valueStringLength, thisString.data }, .Success;
}
