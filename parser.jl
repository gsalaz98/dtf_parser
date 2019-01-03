function read_dtf(file_path::String)::DataFrames.DataFrame
    """
    Helper function that allows you to read DTF files into a DataFrame.
    The DataFrame can then be used to reconstruct the orderbook.
    
    Argument Descriptions:
    
    `file_path::String` : Relative path to file. 
    """
    FLAG_EMPTY = 0b00000000
    FLAG_IS_BID = 0b00000001
    FLAG_IS_TRADE = 0b00000010
    MAGIC_VALUE = [0x44, 0x54, 0x46, 0x90, 0x01]
    RECORD_OFFSET = 96
    
    dtf_file = open(file_path, "r")
    dtf_bytes = UInt8[]
    # Read bytes into a buffer
    readbytes!(dtf_file, dtf_bytes, Inf)
    close(dtf_file)
    
    # We will store our resulting data points in this dataframe and return it
    df = DataFrames.DataFrame(ts = Float64[], seq = UInt64[], is_trade = Bool[], is_bid = Bool[], price = Float64[], volume = Float64[])
    
    # File metadata
    symbol = String(collect(Char, dtf_bytes[6:25]))
    n_records = parse(UInt64, bytes2hex(dtf_bytes[26:33]), base=16)
    max_ts = parse(UInt64, bytes2hex(dtf_bytes[34:41]), base=16)
    
    # We will have regular updates of these values in order to calculate date and seq values
    # from a dataset that has limited precision for storage space purposes.
    ref_ts = parse(UInt64, bytes2hex(dtf_bytes[82:89]), base=16)
    ref_seq = parse(UInt32, bytes2hex(dtf_bytes[90:93]), base=16)
    next_record = parse(UInt16, bytes2hex(dtf_bytes[94:95]), base=16)
        
    if dtf_bytes[1:5] != MAGIC_VALUE
        throw(ArgumentError("File $(file_path) is not a valid DTF file"))
    end
    
    println("Symbol: $(symbol)\n, n_records: $(n_records)\n, max_ts: $(max_ts)\n, ref_ts: $(ref_ts)\n, ref_seq: $(ref_seq)\n, next_record: $(next_record)\n")
    #return
    
    x = RECORD_OFFSET
    i = 1
    
    while true
        # Set to x + 11 so that we don't skip a record by accident at the end of the file
        if length(dtf_bytes) < x + 11
            break
        end
        
        # Check if we've passed our `next_record` count and the current byte is a metadata indicator
        if next_record < i && dtf_bytes[x] == 0x01            
            ref_ts = parse(UInt64, bytes2hex(dtf_bytes[x+1:x+8]), base=16)
            ref_seq = parse(UInt32, bytes2hex(dtf_bytes[x+9:x+12]), base=16)
            next_record = parse(UInt16, bytes2hex(dtf_bytes[x+13:x+14]), base=16)
            
            # Reset record count
            i = 1
            # Jump to the next record available
            x = x + 15
        end
        
        push!(df, [
                # timestamp
                (ref_ts + parse(UInt16, bytes2hex(dtf_bytes[x:x+1]), base=16)) * 0.001,
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
                parse(Float64, string(reinterpret(Float32, reverse(dtf_bytes[x+4:x+7]))[1])),
                # size
                parse(Float64, string(reinterpret(Float32, reverse(dtf_bytes[x+8:x+11]))[1])),
        ])
        
        i = i + 1
        # 12 bytes per row. Jumps to the next row
        x = x + 12
    end
    
    # Sort timestamp in Float format before converting to DateTime
    sort!(df, (:ts));
    # Set :ts field equal to DateTimes
    df[:ts] = Dates.unix2datetime.(df[:ts]);
    
    return df
end
