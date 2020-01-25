local MOD_ADLER = 65521

function adler32(data, len)
    local a = 1
    local b = 0
    local index

    for index=0, len-1, 1 do
        a = (a + data[index+1]) % MOD_ADLER
        b = (b + a) % MOD_ADLER
    end

    return (b << 16) | a
end