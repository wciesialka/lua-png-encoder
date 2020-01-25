
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

local crc_meta = {}

function crc_meta.New(self)

    local CRC = {}

    CRC.value = 0xffffffff

    setmetatable(CRC, crc_meta)

    return CRC
end

function crc_meta.__tostring(self)
    return string.format("0x%X",self.value)
end

crc_meta.__call = crc_meta.New

local crc_meta_index = {}

function crc_meta_index.Update(self, buf, len)

    local c = self.value
    local n

    if(CRCTable == nil) then
        make_crc_table()
    end
            
    for n=0,len-1,1 do
        c = CRCTable[((c ~ buf[n+1]) & 0xFF) + 1] ~ (c >> 8)
    end

    self.value = c
end

function crc_meta_index.GetValue(self)
    return self.value ~ 0xffffffff
end

function crc_meta_index.Reset(self)
    self.value = 0xffffffff
end

crc_meta.__index = crc_meta_index

CRC32 = {}

setmetatable(CRC32,crc_meta)