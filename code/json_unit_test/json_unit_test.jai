/*
Project: Loam
File: json_unit_test.jai
Author: Brock Salmon
Created: 08OCT2025
*/

IS_DEV :: true;

// JSON UNIT TESTS
load_and_parse_json_test_file :: (file : string) -> bool, *JSON_Value, JSON_ErrorType {
    filepath := "C:/work/json-acceptance-tests/";
    fullFilepath := tprint("%1%2.json", filepath, file);
    json, success := read_entire_file(fullFilepath);
    if !success {
	print_color("Failed to read file %\n", fullFilepath, color = .HI_RED);
	return false, null, .Success;
    }

    root, error := json_build_tree(json, tprint("UnitTest_%", file));
    free(json);
    return true, root, error;
}

main :: () {
    print_color("\nRUNNING JSON UNIT TESTS\n\n", color = .HI_MAGENTA);
    timeStart := seconds_since_init();

    single_error_check :: (test : string, file : string, checkError : JSON_ErrorType) #expand {
	read, value, error := load_and_parse_json_test_file(file);
	if !read then `return;

	if error == checkError {
	    print_color("%: Failed as expected\n\n", test, color = .GREEN);
	} else {
	    print_color("%: Did not fail with expected %, error: %\n\n", test, checkError, error, color = .HI_RED);
	}

	json_free_value(value);
    }

    single_error_check("Test 1", "fail1", .FailedToOpenRoot);
    single_error_check("Test 2", "fail2", .FailedToCloseValue);
    single_error_check("Test 3", "fail3", .MalformedKey);
    single_error_check("Test 4", "fail4", .ExtraComma);
    single_error_check("Test 5", "fail5", .ExtraComma);
    single_error_check("Test 6", "fail6", .ExtraComma);
    single_error_check("Test 7", "fail7", .DataAfterClose);
    single_error_check("Test 8", "fail8", .DataAfterClose);
    single_error_check("Test 9", "fail9", .ExtraComma);
    single_error_check("Test 10", "fail10", .DataAfterClose);
    single_error_check("Test 11", "fail11", .InvalidValue);
    single_error_check("Test 12", "fail12", .InvalidValue);
    single_error_check("Test 13", "fail13", .LeadingZeroes);
    single_error_check("Test 14", "fail14", .HexNumber);
    single_error_check("Test 15", "fail15", .InvalidEscape);
    single_error_check("Test 16", "fail16", .InvalidValue);
    single_error_check("Test 17", "fail17", .InvalidEscape);
    single_error_check("Test 18", "fail18", .NoValueSeparator);
    single_error_check("Test 19", "fail19", .InvalidValue);
    single_error_check("Test 20", "fail20", .NoValueSeparator);
    single_error_check("Test 21", "fail21", .FailedToCloseValue);
    single_error_check("Test 22", "fail22", .InvalidValue);
    single_error_check("Test 23", "fail23", .InvalidValue);
    single_error_check("Test 24", "fail24", .InvalidWhitespace);
    single_error_check("Test 25", "fail25", .InvalidEscape);
    single_error_check("Test 26", "fail26", .InvalidWhitespace);
    single_error_check("Test 27", "fail27", .InvalidEscape);
    single_error_check("Test 28", "fail28", .InvalidValue);
    single_error_check("Test 29", "fail29", .InvalidValue);
    single_error_check("Test 30", "fail30", .InvalidValue);
    single_error_check("Test 31", "fail31", .FailedToCloseValue);
    single_error_check("Test 32", "fail32", .FailedToCloseValue);
    
    {
	test := "Test 33";
	read, root, error := load_and_parse_json_test_file("pass1");
	if !read then return;

	if error == .Success {
	    if root && root.values.count == 20 {
		// Check loose values in the root array
		if  root.values[0].value_string == "JSON Test Pattern pass1" &&
		    root.values[2].values.count == 0 &&
		    root.values[3].values.count == 0 &&
		    root.values[4].value_float == -42 &&
		    root.values[5].value_bool == true &&
		    root.values[6].value_bool == false &&
		    root.values[7].value_null == null &&
		    root.values[9].value_float == 0.5 &&
		    root.values[10].value_float == 98.6 &&
		    root.values[11].value_float == 99.44 &&
		    root.values[12].value_float == 1066 &&
		    root.values[13].value_float == 10 &&
		    root.values[14].value_float == 1 &&
		    root.values[15].value_float == 0.1 &&
		    root.values[16].value_float == 1 &&
		    root.values[17].value_float == 2 &&
		    root.values[18].value_float == 2 &&
		    root.values[19].value_string == "rosebud"
		{} else {
		    print_color("%: Succeeded with incorrect results\n\n", test, color = .HI_YELLOW);
		    return;
		}
		
		// Process Objects (indices 1 & 8)
		object := root.values[1];
		if  object.values.count == 1 &&
		    object.values[0].name == "object with 1 member" &&
		    object.values[0].values.count == 1 &&
		    object.values[0].values[0].value_string == "array with 1 element"
		{} else {
		    print_color("%: Succeeded with incorrect results\n\n", test, color = .HI_YELLOW);
		    return;
		}

		object = root.values[8];
		if  object.values.count == 30 &&
		    object.values[0].name == "integer" && object.values[0].value_float == 1234567890 &&
		    object.values[1].name == "real" && object.values[1].value_float == -9876.543210 &&
		    object.values[2].name == "" && object.values[2].value_float == 23456789012 &&
		    object.values[3].name == "zero" && object.values[3].value_float == 0 &&
		    object.values[4].name == "one" && object.values[4].value_float == 1 &&
		    object.values[5].name == "space" && object.values[5].value_string == " " &&
		    object.values[6].name == "quote" && object.values[6].value_string == "\\\"" &&
		    object.values[7].name == "backslash" && object.values[7].value_string == "\\\\" &&
		    object.values[8].name == "controls" && object.values[8].value_string == "\\b\\f\\n\\r\\t" &&
		    object.values[9].name == "slash" && object.values[9].value_string == "/ & \\/" &&
		    object.values[10].name == "alpha" && object.values[10].value_string == "abcdefghijklmnopqrstuvwxyz" &&
		    object.values[11].name == "ALPHA" && object.values[11].value_string == "ABCDEFGHIJKLMNOPQRSTUVWXYZ" &&
		    object.values[12].name == "digit" && object.values[12].value_string == "0123456789" &&
		    object.values[13].name == "0123456789" && object.values[13].value_string == "digit" &&
		    object.values[14].name == "special" && object.values[14].value_string == "`1~!@#$%^&*()_+-={':[,]}|;.</>?" &&
		    object.values[15].name == "hex" && object.values[15].value_string == "\\u0123\\u4567\\u89AB\\uCDEF\\uabcd\\uef4A" &&
		    object.values[16].name == "true" && object.values[16].value_bool == true &&
		    object.values[17].name == "false" && object.values[17].value_bool == false &&
		    object.values[18].name == "null" && object.values[18].value_null == null &&
		    object.values[19].name == "array" && object.values[19].type == .Array &&
		    object.values[20].name == "object" && object.values[20].type == .Object &&
		    object.values[21].name == "address" && object.values[21].value_string == "50 St. James Street" &&
		    object.values[22].name == "url" && object.values[22].value_string == "http://www.JSON.org/" &&
		    object.values[23].name == "comment" && object.values[23].value_string == "// /* <!-- --" &&
		    object.values[24].name == "# -- --> */" && object.values[24].value_string == " " &&
		    object.values[27].name == "jsontext" && object.values[27].value_string == "{\\\"object with 1 member\\\":[\\\"array with 1 element\\\"]}" &&
		    object.values[28].name == "quotes" && object.values[28].value_string == "&#34; \\u0022 %22 0x22 034 &#x22;" &&
		    object.values[29].name == "\\/\\\\\\\"\\uCAFE\\uBABE\\uAB98\\uFCDE\\ubcda\\uef4A\\b\\f\\n\\r\\t`1~!@#$%^&*()_+-=[]{}|;:',./<>?" && object.values[29].value_string == "A key can be any string"
		{} else {
		    print_color("%: Succeeded with incorrect results\n\n", test, color = .HI_YELLOW);
		    return;
		}

		// Handle Arrays in Object at root index 8
		if  object.values[25].name == " s p a c e d " && object.values[25].values.count == 7 &&
		    object.values[25].values[0].value_float == 1 && object.values[25].values[1].value_float == 2 &&
		    object.values[25].values[2].value_float == 3 && object.values[25].values[3].value_float == 4 &&
		    object.values[25].values[4].value_float == 5 && object.values[25].values[5].value_float == 6 &&
		    object.values[25].values[6].value_float == 7 &&
		    object.values[26].name == "compact" && object.values[26].values.count == 7 &&
		    object.values[26].values[0].value_float == 1 && object.values[26].values[1].value_float == 2 &&
		    object.values[26].values[2].value_float == 3 && object.values[26].values[3].value_float == 4 &&
		    object.values[26].values[4].value_float == 5 && object.values[26].values[5].value_float == 6 &&
		    object.values[26].values[6].value_float == 7
		{
		    print_color("%: Succeeded as expected\n\n", test, color = .GREEN);
		} else {
		    print_color("%: Succeeded with incorrect results\n\n", test, color = .HI_YELLOW);
		    return;
		}
	    } else {
		print_color("%: Succeeded with incorrect results\n\n", test, color = .HI_YELLOW);
		return;
	    }
	} else {
	    print_color("%: Failed with error: %\n\n", test, error, color = .HI_RED);
	}

	json_free_value(root);
    }
    
    {
	test := "Test 34";
	read, value, error := load_and_parse_json_test_file("pass2");
	if !read then return;

	if error == .Success {
	    checkString, found := json_get(value.values[0].values[0].values[0].values[0].values[0].values[0].values[0].values[0].values[0]
					   .values[0].values[0].values[0].values[0].values[0].values[0].values[0].values[0].values[0].values[0], string);
	    if found && compare(checkString, "Not too deep") == 0 {
		print_color("%: Succeeded as expected\n\n", test, color = .GREEN);
	    } else {
		print_color("%: Succeeded with incorrect results\n\n", test, color = .HI_YELLOW);
	    }
	} else {
	    print_color("%: Failed with error: %\n\n", test, error, color = .HI_RED);
	}

	json_free_value(value);
    }

    {
	test := "Test 35";
	read, value, error := load_and_parse_json_test_file("pass3");
	if !read then return;

	if error == .Success {
	    if value && value.values.count == 1 && compare(value.values[0].name, "JSON Test Pattern pass3") == 0 {
		object := value.values[0];
		if object && object.values.count == 2 {
		    firstValue := object.values[0];
		    secondValue := object.values[1];
		    
		    if firstValue && compare(firstValue.name, "The outermost value") == 0 {
			stringValue, found := json_get(firstValue, string);
			if !found || compare(stringValue, "must be an object or array.") != 0 {
			    print_color("%: Succeeded with incorrect results: Failed to get value for firstValue: % : %\n\n", test, firstValue.name, stringValue, color = .HI_YELLOW);
			    stringValue, found = json_get(secondValue, string);
			    print_color("secondValue: % : %\n\n", secondValue.name, stringValue, color = .HI_YELLOW);
			    return;
			}
		    } else {
			print_color("%: Succeeded with incorrect results: First value is invalid or has the wrong key\n\n", test, color = .HI_YELLOW);
			return;
		    }
		    
		    if secondValue && compare(secondValue.name, "In this test") == 0 {
			stringValue, found := json_get(secondValue, string);
			if !found || compare(stringValue, "It is an object.") != 0 {
			    print_color("%: Succeeded with incorrect results: Failed to get value for secondValue\n\n", test, color = .HI_YELLOW);
			    return;
			}
		    } else {
			print_color("%: Succeeded with incorrect results: Second value is invalid or has the wrong key\n\n", test, color = .HI_YELLOW);
			return;
		    }

		    print_color("%: Succeeded as expected\n\n", test, color = .GREEN);
		} else {
		    print_color("%: Succeeded with incorrect results: Invalid object\n\n", test, color = .HI_YELLOW);
		}
	    } else {
		print_color("%: Succeeded with incorrect results: Invalid root object\n\n", test, color = .HI_YELLOW);
	    }
	} else {
	    print_color("%: Failed with error: %\n\n", test, error, color = .HI_RED);
	}

	json_free_value(value);
    }
    
    print_color("SUCCESSFULLY RAN JSON TESTS\n\n", color = .HI_GREEN);
}



#scope_file

#load "../json.jai";

#import "Basic";
#import "File";
#import "File_Utilities";
#import "Hash_Table";
#import "Math";
#import "Print_Color";
#import "Reflection";
#import "String";

#import "Logger" (IS_DEV);

