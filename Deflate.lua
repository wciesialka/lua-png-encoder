-- big thanks to Dan Kogai for his JavaScript implementation of the Deflate algorithm,
-- which i used for reference.

local function Array(n) -- function to create a table with a preset length, like a C-style array
    local t = {}
    for i=1,n,1 do
        table.insert(t,nil)
    end
    return t
end

local function Array_Function(n,f,...)
    local t = {}
    for i=1,n,1 do
        table.insert(t,f(...))
    end
    return t
end

-- constants
local zip_WSIZE = 32768
local zip_STORED_BLOCK = 0
local zip_STATIC_TREES = 1
local zip_DYN_TREES    = 2

-- deflate variables
local zip_DEFAULT_LEVEL = 6
local zip_FULL_SEARCH = true
local zip_INBUFSIZ = 32768
local zip_INBUF_EXTRA = 64
local zip_OUTBUFSIZ = 1024 * 8
local zip_window_size = 2 * zip_WSIZE
local zip_MIN_MATCH = 3
local zip_MAX_MATCH = 258
local zip_BITS = 16

-- we don't want to use too much memory

local zip_LIT_BUFSIZE = 0x2000
local zip_HASH_BITS = 13

local zip_DIST_BUFSIZE = zip_LIT_BUFSIZE
local zip_HASH_SIZE = 1 << zip_HASH_BITS
local zip_HASH_MASK = zip_HASH_SIZE - 1
local zip_WMASK = zip_WSIZE - 1
local zip_NIL = 0
local zip_TOO_FAR = 4096
local zip_MIN_LOOKAHEAD = zip_MAX_MATCH + zip_MIN_MATCH + 1
local zip_MAX_DIST = zip_WSIZE - zip_MIN_LOOKAHEAD
local zip_SMALLEST = 1
local zip_MAX_BITS = 15
local zip_MAX_BL_BITS = 7
local zip_LENGTH_CODES = 29
local zip_LITERALS =256
local zip_END_BLOCK = 256
local zip_L_CODES = zip_LITERALS + 1 + zip_LENGTH_CODES
local zip_D_CODES = 30
local zip_BL_CODES = 19
local zip_REP_3_6 = 16
local zip_REPZ_3_10 = 17
local zip_REPZ_11_138 = 18
local zip_HEAP_SIZE = 2 * zip_L_CODES + 1
local zip_H_SHIFT = math.floor((zip_HASH_BITS + zip_MIN_MATCH - 1) / zip_MIN_MATCH)

local zip_DYN_DTREE_SIZE = 2*zip_D_CODES+1
local zip_BL_TREE_SIZE = 2*zip_BL_CODES+1
local zip_LENGTH_CODE_LENGTH = zip_MAX_MATCH-zip_MIN_MATCH

-- our variables

local zip_free_queue
local zip_qhead, zip_qtail
local zip_initflag
local zip_outbuf = nil
local zip_outcnt, zip_outoff
local zip_complete
local zip_window
local zip_d_buf
local zip_l_buf
local zip_prev
local zip_bi_buf
local zip_bi_valid
local zip_block_start
local zip_ins_h
local zip_hash_head
local zip_prev_match
local zip_match_available
local zip_match_length
local zip_prev_length
local zip_strstart
local zip_match_start
local zip_eofile
local zip_lookahead
local zip_max_chain_length
local zip_max_lazy_match
local zip_compr_level
local zip_good_match
local zip_nice_match
local zip_dyn_ltree
local zip_dyn_dtree
local zip_static_ltree
local zip_static_dtree
local zip_bl_tree
local zip_l_desc
local zip_d_desc
local zip_bl_desc
local zip_bl_count
local zip_heap
local zip_heap_len
local zip_heap_max
local zip_depth
local zip_length_code
local zip_dist_code
local zip_base_length
local zip_base_dist
local zip_flag_buf
local zip_last_lit
local zip_last_dist
local zip_last_flags
local zip_flags
local zip_flag_bit
local zip_opt_len
local zip_static_len
local zip_deflate_data
local zip_deflate_pos

-- tables

function zip_DeflateCT()
    return {
        fc = 0, -- frequency count or bit string
        dl = 0  -- father node in Huffman tree or length of bit string
    }
end

function zip_DeflateTreeDesc()
    return {
        dyn_tree = nil,
        static_tree = nil,
        extra_bits = nil,
        extra_base = nil,
        elems = 0,
        max_length = 0,
        max_code = 0
    }
end

function zip_DeflateConfiguration(a,b,c,d)
    return {
        good_length = a,
        max_lazy = b,
        nice_length = c,
        max_chain = d
    }
end

function zip_DeflateBuffer()
    return {
        next = nil,
        len = 0,
        ptr = Array(zip_OUTBUFSIZ),
        off = 0
    }
end

-- constant tables

local zip_extra_lbits = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local zip_extra_dbits = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
local zip_extra_blbits = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,7}
local zip_bl_order = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}
local zip_configuration_table = {
    zip_DeflateConfiguration(0,0,0,0),
    zip_DeflateConfiguration(4,4,8,4),
    zip_DeflateConfiguration(4,5,16,8),
    zip_DeflateConfiguration(4,6,32,32),
    zip_DeflateConfiguration(4,4,16,16),
    zip_DeflateConfiguration(8,16,32,32),
    zip_DeflateConfiguration(8,16,128,128),
    zip_DeflateConfiguration(8,32,128,256),
    zip_DeflateConfiguration(32,128,258,1024),
    zip_DeflateConfiguration(32,258,258,4096)
}

-- functions

function zip_deflate_start(level)
    local i

    if(level == nil) then
        level = zip_DEFAULT_LEVEL
    elseif(level < 1) then
        level = 1
    elseif(level > 9) then
        level = 9
    end

    zip_compr_level = level
    zip_initflag = false
    zip_eofile = false
    if(zip_outbuf != nil) then
        return
    end

    zip_free_queue = nil
    zip_qhead = nil
    zip_qtail = nil

    zip_outbuf = Array(zip_OUTBUFSIZ)
    zip_window = Array(zip_window_size)
    zip_d_buf = Array(zip_DIST_BUFSIZE)
    zip_l_buf = Array(zip_INBUFSIZ + zip_INBUF_EXTRA)
    zip_prev = Array(1 << zip_BITS)

    zip_dyn_ltree = Array_Function(zip_HEAP_SIZE,zip_DeflateCT)
    zip_dyn_dtree = Array_Function(zip_DYN_DTREE_SIZE,zip_DeflateCT)
    zip_static_ltree = Array_Function(zip_L_CODES+2,zip_DeflateCT)
    zip_static_dtree = Array_Function(zip_D_CODES,zip_DeflateCT)
    zip_bl_tree = Array_Function(zip_BL_TREE_SIZE,zip_DeflateCT)

    zip_l_desc = zip_DeflateTreeDesc()
    zip_d_desc = zip_DeflateTreeDesc()
    zip_bl_desc = zip_zip_DeflateTreeDesc()

    zip_bl_count = Array(zip_MAX_BITS+1)
    zip_heap = Array(zip_HEAP_SIZE)
    zip_depth = Array(zip_HEAP_SIZE)
    zip_length_code = Array(zip_LENGTH_CODE_LENGTH)
    zip_dist_code = Array(512)
    zip_base_length = Array(zip_D_CODES)
    zip_flag_buf = Array(math.floor(zip_LIT_BUFSIZE / 8))
end

function zip_deflate_end()
    zip_free_queue = nil
    zip_qhead = nil
    zip_qtail = nil
    zip_outbuf = nil
    zip_window = nil
    zip_d_buf = nil
    zip_l_buf = nil
    zip_prev = nil
    zip_dyn_ltree = nil
    zip_dyn_dtree = nil
    zip_static_ltree = nil
    zip_static_dtree = nil
    zip_bl_tree = nil
    zip_l_desc = nil
    zip_d_desc = nil
    zip_bl_desc = nil
    zip_bl_count = nil
    zip_heap = nil
    zip_depth = nil
    zip_length_code = nil
    zip_dist_code = nil
    zip_base_length = nil
    zip_base_dist = nil
    zip_flag_buf = nil
end