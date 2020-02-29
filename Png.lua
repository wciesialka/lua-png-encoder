require('Color')
require('crc')

local png_meta = {}

local function Recursive_Push(target,value)
    if(type(val) == "table") then
        for _,v in pairs(val) do
            if(type(v) == "table") then
                Recursive_Push(target,v)
            else
                table.insert(target,v,#target)
            end
        end
    else
        table.insert(target,val,#target)
    end
end

function png_meta.New(self,width,height)
    local png = {}

    png.width  = width
    png.height = height
    png.buffer = {137,80,78,71,13,10,26,10} -- file signature
    png.current_width = 0
    png.current_height = 0
    png.filter = 0
    png.bit_depth = 8
    png.color_type = 6
    png.compression_method = 0
    png.interlace_method = 0

    png.img = {}

    png.crc = CRC32()

    setmetatable(png, png_meta)

    return png
end

png_meta.__call = png_meta.New

png_index = {}

png_meta.__index = png_index

-- Add Pixel
-- Expects a Color metatable

function png_index.Add_Pixel(self,pixel)
    if(self.current_height == self.height) then
        error("Cannot add any more pixels to PNG, width and height met.")
    else
        if(self.current_width == 0) then
            table.insert(self.img,self.filter)
        end
        table.insert(self.img,pixel.r)
        table.insert(self.img,pixel.g)
        table.insert(self.img,pixel.b)
        table.insert(self.img,pixel.a)
        self.current_width = self.current_width + 1
        if(self.current_width == self.width) then
            self.current_height = self.current_height + 1
            self.current_width = 0
        end
    end
end

-- Add Image
-- Expects a 2D array of color metatables

function png_index.Add_Image(self,image)
    for _,row in pairs(image) do
        for _,pixel in pairs(row) do
            self:Add_Pixel(pixel)
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
    Recursive_Push( buf, self.bit_depth ) -- bit depth (1 byte)
    Recursive_Push( buf, self.color_type ) -- color type (1 byte)
    Recursive_Push( buf, self.compression_method ) -- compression method (1 byte)
    Recursive_Push( buf, self.filter ) -- filter type (1 byte)
    Recursive_Push( buf, self.interlace_method ) -- interlace method (1 byte)

    self:Add_Chunk(type,buf)
end

function png_index.Add_End(self)
    local type = {0x49,0x45,0x4e,0x44} -- IEND

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

Png = {}
setmetatable(Png,png_meta)