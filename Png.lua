include('Color')
include('crc')

local png_meta = {}

local function Recursive_Push(target,value)
    if(type(val) == "table") then
        for _,v in pairs(val) do
            if(type(v) == "table") then
                Recursive_Push(target,v)
            else
                table.insert(target,v)
            end
        end
    else
        table.insert(target,val)
    end
end

function png_meta.New(self)
    local png = {}

    png.width  = nil
    png.height = nil
    png.buffer = {137,80,78,71,13,10,26,10} -- file signature

    png.image = nil

    png.crc = CRC32()

    setmetatable(png, png_meta)

    return png
end

png_meta.__call = png_meta.New

png_index = {}

png_meta.__index = png_index

-- Load_Image()
-- Expects a 2D array of Color metatables

function png_index.Load_Image(self,image)
    self.height = #image
    self.width =  #image[0]

    self.img = {}
    for _,row in pairs(image) do
        table.insert(img,0)
        for _,pix in pairs(row) do
            table.insert(img,pix:GetR())
            table.insert(img,pix:GetG())
            table.insert(img,pix:GetB())
            table.insert(img,pix:GetA())
        end
    end
end

function png_index.Add_Chunk(self,type,data)
    self.crc:Reset()
    self.crc:Update(type,#type)
    self.crc:Update(data,#data)

    local len = self:As_4_Bytes(#data)
    self:Add_To_Buffer(len)

    self:Add_To_Buffer(type)

    self:Add_To_Buffer(data)

    self:Add_To_Buffer( self:As_4_Bytes( self.crc:GetValue() ) )
end


function png_index.Add_Header(self)
    local type = {49,48,44,52} -- IHDR
    local buf = {}
    Recursive_Push( buf, self:As_4_Bytes( self.width  ) ) -- width (4 bytes)
    Recursive_Push( buf, self:As_4_Bytes( self.height ) ) -- height (4 bytes)
    Recursive_Push( buf, 8 ) -- bit depth (1 byte)
    Recursive_Push( buf, 6 ) -- color type (1 byte)
    Recursive_Push( buf, 0 ) -- compression method (1 byte)
    Recursive_Push( buf, 0 ) -- filter type (1 byte)
    Recursive_Push( buf, 0 ) -- interlace method (1 byte)

    self:Add_Chunk(type,buf)
end

function png_index.Add_End(self)
    local type = {49,45,4e,44} -- IEND

    self:Add_Chunk(type,{})
end

function png_index.Add_To_Buffer(self,val)
    Recursive_Push(self.buffer,val)
end

function png_index.As_4_Bytes(self, i)
    return {
        (i >> 24) & 0xFF,
        (i >> 16) & 0xFF,
        (i >>  8) & 0xFF,
         i        & 0xFF
    }
end

function png_index.As_2_Bytes(self, i)
    return {
        (i >>  8) & 0xFF,
         i        & 0xFF
    }
end