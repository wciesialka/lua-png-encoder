
local LONG_SIZE = 32
local POLYNOMIAL = 0xEDB88320

local CRCTable = nil

function make_crc_table()

    CRCTable = {}

    local c, n, k

    for n=0, 255, 1 do
        c = n
        for k=0, 7, 1 do
            if(c & 1 == 1) then
                c = POLYNOMIAL ~ (c >> 1)
            else
                c = c >> 1
            end
        end
        CRCTable[n+1] = c
    end
end

function update_crc(crc, buf, len)

    local c = crc
    local n

    if(CRCTable == nil) then
        make_crc_table()
    end
            
    for n=0,len-1,1 do
        c = CRCTable[((c ~ buf[n+1]) & 0xFF) + 1] ~ (c >> 8)
    end

    return c
end

function crc(buf, len)
    return update_crc(0xffffffff,buf,len) ~ 0xffffffff
end
