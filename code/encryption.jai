/*
Project: Loam Engine
File: encryption.jai
Author: Brock Salmon
Created: 25OCT2025
*/

/*
ENCRYPTION INFO

Directory Files:
File code and encryption key is left unencrypted

Pack Files:
Everything is encrypted via the directory encryption key

Core Files:
Everything is encrypted via the core encryption key built into the engine
*/

EncryptionKey :: u32;

CORE_ENCRYPT_KEY : EncryptionKey : 3_466_981_129;
CORE_IS_ENCRYPTED :: true;

encrypt_data :: (data : *string, key : EncryptionKey) {
    start := seconds_since_init();
    for * data.* {
	byteIndex := it_index % size_of(EncryptionKey);
	shift := 8 * byteIndex;
	keyByte := cast(u8) ((key >> shift) & 0xFF);

	it.* += keyByte;
	it.* = (it.* << 4) | (it.* >> 4);
	it.* -= (keyByte * 2);
    }
    taken := seconds_since_init() - start;
    print_color("encrypt_data: %ms\n", taken * 1000.0, color=.HI_YELLOW);
}

unencrypt_data :: (data : *string, key : EncryptionKey) {
    start := seconds_since_init();
    for * data.* {
	byteIndex := it_index % size_of(EncryptionKey);
	shift := 8 * byteIndex;
	keyByte := cast(u8) ((key >> shift) & 0xFF);

	it.* += (keyByte * 2);
	it.* = (it.* << 4) | (it.* >> 4);
	it.* -= keyByte;
    }
    taken := seconds_since_init() - start;
    print_color("decrypt_data: %ms\n", taken * 1000.0, color=.HI_MAGENTA);
}

generate_encryption_key :: () -> EncryptionKey {
    if context.random_state.low == 0 && context.random_state.high == 0 {
	time := current_time_consensus();
	context.random_state = .{ time.low | 1, cast,no_check(u64) time.high };
    }
    
    while true {
	key64 := random_get();
	key : EncryptionKey = cast(u32)(key64 & 0xFFFFFFFF);
	allBytesValid := true;
	for 0 .. 3 {
	    byteIndex := it % size_of(EncryptionKey);
	    shift := 8 * byteIndex;
	    keyByte := cast(u8) ((key >> shift) & 0xFF);
	    
	    if keyByte <= 1 {
		allBytesValid = false;
		break;
	    }
	}

	if allBytesValid then return key;
    }

    return 0;
}
