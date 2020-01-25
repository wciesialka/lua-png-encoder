local color_meta = {}

local function round(x)
    return x + 0.5 - (x + 0.5) % 1 -- this will round x to the nearest whole integer
end

function color_meta.New(self, r, g, b, a)

    if(r == nil) then
        r = 0
    elseif(type(r) != "number") then
        error("Invalid argument passed to Color.New(). Argument 1 must be a number.")
    elseif(r < 0 or r > 255) then
        error("Invalid argument passed to Color.New(). Argument 1 must be between 0 and 255 inclusive.")
    else
        r = round(r)
    end

    if(g == nil) then
        g = 0
    elseif(type(g) != "number") then
        error("Invalid argument passed to Color.New(). Argument 2 must be a number.")
    elseif(g < 0 or g > 255) then
        error("Invalid argument passed to Color.New(). Argument 2 must be between 0 and 255 inclusive.")
    else
        g = round(g)
    end

    if(b == nil) then
        b = 0
    elseif(type(b) != "number") then
        error("Invalid argument passed to Color.New(). Argument 3 must be a number.")
    elseif(b < 0 or b > 255) then
        error("Invalid argument passed to Color.New(). Argument 3 must be between 0 and 255 inclusive.")
    else
        b = round(b)
    end

    if(a == nil) then
        a = 255
    elseif(type(a) != "number") then
        error("Invalid argument passed to Color.New(). Argument 4 must be a number.")
    elseif(a < 0 or a > 255) then
        error("Invalid argument passed to Color.New(). Argument 4 must be between 0 and 255 inclusive.")
    else
        a = round(a)
    end


    local color = {} -- create a new color

    color.r = r
    color.g = g
    color.b = b
    color.a = a

    setmetatable(color, color_meta)

    return color
end

color_meta.__call = color_meta.New

function color_meta.__tostring( self )
    
    return string.format( "(%i,%i,%i,%i)", self.r, self.g, self.b, self.a )

end

local color_meta_index = {}

function color_meta_index.SetR(self,v)
    if(v == nil) then
        error("Invalid argument passed to Color:SetR(). Argument 1 cannot be nil.")
    elseif(type(v) != "number") then
        error("Invalid argument passed to Color:SetR(). Argument 1 must be a number.")
    elseif(v < 0 or v > 255) then
        error("Invalid argument passed to Color:SetR(). Argument 1 must be between 0 and 255 inclusive.")
    else
        self.r = round(v)
    end
end

function color_meta_index.SetG(self,v)
    if(v == nil) then
        error("Invalid argument passed to Color:SetG(). Argument 1 cannot be nil.")
    elseif(type(v) != "number") then
        error("Invalid argument passed to Color:SetG(). Argument 1 must be a number.")
    elseif(v < 0 or v > 255) then
        error("Invalid argument passed to Color:SetG(). Argument 1 must be between 0 and 255 inclusive.")
    else
        self.g = round(v)
    end
end

function color_meta_index.SetB(self,v)
    if(v == nil) then
        error("Invalid argument passed to Color:SetB(). Argument 1 cannot be nil.")
    elseif(type(v) != "number") then
        error("Invalid argument passed to Color:SetB(). Argument 1 must be a number.")
    elseif(v < 0 or v > 255) then
        error("Invalid argument passed to Color:SetB(). Argument 1 must be between 0 and 255 inclusive.")
    else
        self.b = round(v)
    end
end

function color_meta_index.SetA(self,v)
    if(v == nil) then
        error("Invalid argument passed to Color:SetA(). Argument 1 cannot be nil.")
    elseif(type(v) != "number") then
        error("Invalid argument passed to Color:SetA(). Argument 1 must be a number.")
    elseif(v < 0 or v > 255) then
        error("Invalid argument passed to Color:SetA(). Argument 1 must be between 0 and 255 inclusive.")
    else
        self.a = round(v)
    end
end

function color_meta_index.GetR(self)
    return self.r
end

function color_meta_index.GetG(self)
    return self.g
end

function color_meta_index.GetB(self)
    return self.b
end

function color_meta_index.GetA(self)
    return self.a
end

function color_meta_index.Integer(self)
    return (self.r << 24) | (self.g << 16) | (self.b << 8) | (self.a)
end

color_meta.__index = color_meta_index

Color = {}

setmetatable(Color, color_meta)