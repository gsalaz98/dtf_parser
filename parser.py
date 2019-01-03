def read_dtf(file_path):
    """
    Helper function that allows you to read DTF files into a DataFrame.
    The DataFrame can then be used to reconstruct the orderbook.
    
    Argument Descriptions:
    
    `file_path::str` : Relative path to file. 
    """
    FLAG_EMPTY = 0b00000000
    FLAG_IS_BID = 0b00000001
    FLAG_IS_TRADE = 0b00000010
    MAGIC_VALUE = bytes([0x44, 0x54, 0x46, 0x90, 0x01])
    RECORD_OFFSET = 95
    
    dtf_file = open(file_path, 'rb')
    dtf_bytes = bytes(dtf_file.read())
    # Read bytes into a buffer
    dtf_file.close()
    
    # We will store our resulting data points in this list and
    # construct a dataframe once it is filled
    df_list = []
    
    # File metadata
    symbol = dtf_bytes[5:25].decode('utf-8')
    n_records = int.from_bytes(dtf_bytes[25:33], byteorder='big', signed=False)
    max_ts = int.from_bytes(dtf_bytes[33:41], byteorder='big', signed=False)
    
    # We will have regular updates of these values in order to calculate date and seq values
    # from a dataset that has limited precision for storage space purposes.
    ref_ts = int.from_bytes(dtf_bytes[81:89], byteorder='big', signed=False)
    ref_seq = int.from_bytes(dtf_bytes[89:93], byteorder='big', signed=False)
    next_record = int.from_bytes(dtf_bytes[93:95], byteorder='big', signed=False)
        
    if dtf_bytes[0:5] != MAGIC_VALUE:
        raise Exception("File %s is not a valid DTF file" % file_path)
    
    x = RECORD_OFFSET
    i = 1
    
    while True:
        # Set to x + 11 so that we don't skip a record by accident at the end of the file
        if len(dtf_bytes) < x + 12:
            break
        
        # Check if we've passed our `next_record` count and the current byte is a metadata indicator
        if next_record < i and dtf_bytes[x] == 0x01:            
            ref_ts = int.from_bytes(dtf_bytes[x+1:x+9], byteorder='big', signed=False)
            ref_seq = int.from_bytes(dtf_bytes[x+9:x+13], byteorder='big', signed=False)
            next_record = int.from_bytes(dtf_bytes[x+13:x+15], byteorder='big', signed=False)
            
            # Reset record count
            i = 1
            # Jump to the next record available
            x = x + 15
        
        df_list.append([
                # timestamp
                (ref_ts + int.from_bytes(dtf_bytes[x:x+2], byteorder='big', signed=False)) * 0.001,
                # seq count
                ref_seq + dtf_bytes[x+2], # seq count 
                # is trade
                (dtf_bytes[x+3] & FLAG_IS_TRADE) == FLAG_IS_TRADE,
                # is bid
                (dtf_bytes[x+3] & FLAG_IS_BID) == FLAG_IS_BID, 

                # Reverse the bytes to convert them into little endian before parsing the int bytes as a float
                # Hacky way to convert Float32 into Float64 values accurately
                # ----------------------
                # price
                struct.unpack('>f', dtf_bytes[x+4:x+8])[0],
                # size
                struct.unpack('>f', dtf_bytes[x+8:x+12])[0]
        ])
        
        i = i + 1
        # 12 bytes per row. Jumps to the next row
        x = x + 12
    
    df = df = pd.DataFrame(df_list, columns=['ts', 'seq', 'is_trade', 'is_bid', 'price', 'volume'])
    df = df.sort_values('ts')
    df['ts'] = pd.to_datetime(df['ts'], unit='s')
    df = df.set_index('ts')
    df = df.set_index('seq', append=True)

    return df
