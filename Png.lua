require('Color')
require('crc')
require('Deflate')
require('adler')

local png_meta = {}

local function Recursive_Push(target,val)
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
    png.i = 1

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
            self.img[self.i] = self.filter
            self.i = self.i + 1
        end
        self.img[self.i] = pixel.r
        self.img[self.i + 1] = pixel.g
        self.img[self.i + 2] = pixel.b
        if(pixel.a ~= nil) then
            self.img[self.i + 3] = pixel.a
        else
            self.img[self.i + 3] = 0
        end
        self.i = self.i + 4
        self.current_width = self.current_width + 1
        if(self.current_width == self.width) then
            self.current_height = self.current_height + 1
            self.current_width = 0
        end
    end
end

local MAX_AREA = 256

function png_index.Write(self,path)
    if(path == nil) then
        path="out.png"
    end
    self.buffer = {0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A} -- File signature
    self:Add_Header()
    local i = 1
    local j = 100
    local area = self.width * self.height * 4
    repeat
        self:Add_IDAT(i,j)
        i = j + 1
        j = math.max(j + 100,area)
    until (j > area)
    self:Add_End()
    local out = io.open("test.png","wb")
    for i=1,#self.buffer,1 do
        out:write(string.char(self.buffer[i]))
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
    local type = {0x49,0x48,0x44,0x52} -- IHDR
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

function png_index.Add_IDAT(self,start,endpos)
    local type = {0x49,0x44,0x41,0x54}
    local idat = {8,3}
    local splice ={}
    for i=start,endpos,1 do
        table.insert( splice, self.img[i] )
    end
    local compressed = zip_deflate(splice)
    Recursive_Push(idat, compressed)
    local check = adler32(compressed,#compressed)
    Recursive_Push(self:As_4_Bytes(check),idat)
    self:Add_Chunk(type,idat)
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