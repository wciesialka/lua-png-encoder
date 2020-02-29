local function Array(n) -- function to create a table with a preset length, like a C-style array
    local t = {}
    for i=1,n,1 do
        table.insert(t,0)
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
local zip_Buf_size = 16

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
    if(zip_outbuf ~= nil) then
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
    zip_bl_desc = zip_DeflateTreeDesc()

    zip_bl_count = Array(zip_MAX_BITS+1)
    zip_heap = Array(zip_HEAP_SIZE)
    zip_depth = Array(zip_HEAP_SIZE)
    zip_length_code = Array(zip_LENGTH_CODE_LENGTH)
    zip_dist_code = Array(512)
    zip_base_length = Array(zip_LENGTH_CODES)
    zip_base_dist = Array(zip_D_CODES)
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

function zip_reuse_queue(p)
    p.next = zip_free_queue
    zip_free_queue = p 
end

function zip_new_queue()
    local p

    if(not zip_free_queue == nil) then
        p = zip_free_queue
        zip_free_queue = zip_free_queue.next
    else
        p = zip_DeflateBuffer()
    end

    p.next = nil
    p.len = 0
    p.off = 0

    return p
end

function zip_head1(i)
    return zip_prev[zip_WSIZE + i+1]
end

function zip_head2(i, val)
    zip_prev[zip_WSIZE + i+1] = val
    return zip_prev[zip_WSIZE + i+1]
end

function zip_put_byte(c)
    zip_outcnt = zip_outcnt + 1
    zip_outbuf[zip_outoff + zip_outcnt+1] = c
    if(zip_outoff + zip_outcnt == zip_OUTBUFSIZ) then
        zip_qoutbuf()
    end
end

function zip_put_short(w)
    w = w & 0xFFFF
    if(zip_outoff + zip_outcnt < zip_OUTBUFSIZ - 2) then
        zip_outcnt = zip_outcnt + 1
        zip_outbuf[zip_outoff + zip_outcnt+1] = (w & 0xFF)
        zip_outcnt = zip_outcnt + 1
        zip_outbuf[zip_outoff + zip_outcnt+1] = (w >> 8)
        zip_outcnt = zip_outcnt + 1
    else
        zip_put_byte(w & 0xff)
        zip_put_byte(w >> 8)
    end
end

-- Insert string s in the dictionary and set match_head to the previous head
-- of the hash chain (the most recent string with same hash key). Return
-- the previous length of the hash chain.
function zip_INSERT_STRING()
    zip_ins_h = ((zip_ins_h << zip_H_SHIFT) ~ (zip_window[zip_strstart + zip_MIN_MATCH - 1+1] & 0xff)) & zip_HASH_MASK
    zip_hash_head = zip_head1(zip_ins_h)
    zip_prev[zip_strstart & zip_WMASK+1] = zip_hash_head
    zip_head2(zip_ins_h, zip_strstart)
end

function zip_SEND_CODE(c, tree)
    zip_send_bits(tree[c+1].fc, tree[c+1].dl)
end

function zip_D_CODE(dist)
    if(dist < 256) then
        return zip_dist_code[dist+1] & 0xFF
    else
        return zip_dist_code[256+(dist >> 7)+1] & 0xFF
    end
end

function zip_SMALLER(tree, n, m)
    return (tree[n+1].fc < tree[m+1].fc) or (tree[n+1].fc == tree[m+1].fc and zip_depth[n+1] <= zip_depth[m+1])
end

function zip_read_buff(buff, offset, n)
    local i = 0
    while(i < n and zip_deflate_pos < #zip_deflate_data) do
        zip_deflate_pos = zip_deflate_pos + 1
        buff[offset + i+1] = string.byte(zip_deflate_data,zip_deflate_pos,zip_deflate_pos) & 0xFF
        i = i+1
    end

    return i
end

function zip_lm_init()
    local j

    for _j=0,zip_HASH_SIZE-1,1 do
        j=_j
        zip_prev[zip_WSIZE + j+1] = 0
    end

    zip_max_lazy_match = zip_configuration_table[zip_compr_level+1].max_lazy
    zip_good_match = zip_configuration_table[zip_compr_level+1].good_length
    if(not zip_FULL_SEARCH) then
        zip_nice_match = zip_configuration_table[zip_compr_level+1].nice_length
    end

    zip_max_chain_length = zip_configuration_table[zip_compr_level+1].max_chain

    zip_strstart = 0
    zip_block_start = 0

    zip_lookahead = zip_read_buff(zip_window, 0, 2 * zip_WSIZE)
    if(zip_lookahead <= 0) then
        zip_eofile = true
        zip_lookahead = 0
        return
    end

    zip_eofile = false

    while(zip_lookahead < zip_MIN_LOOKAHEAD and (not zip_eofile)) do
        zip_fill_window()
    end

    zip_ins_h = 0
    for _j=0,zip_MIN_MATCH - 2, 1 do
        j=_j
        zip_ins_h = ((zip_ins_h << zip_H_SHIFT) ~ (zip_window[j+1] & 0xFF))
    end
end

function zip_longest_match(cur_match)
    local chain_length = zip_max_chain_length
    local scanp = zip_strstart
    local matchp
    local len
    local best_len = zip_prev_length

    local zip_lm_init
    if(zip_strstart > zip_MAX_DIST) then
        limit = zip_strstart - zip_MAX_DIST
    else
        limit = zip_NIL
    end

    local strendp = zip_strstart + zip_MAX_MATCH
    local scan_end1 = zip_window[scanp + best_len- 1+1]
    local scan_end = zip_window[scanp + best_len+1]

    local continue = false

    if(zip_prev_length >= zip_good_match) then
        chain_length = chain_length >> 2
    end

    repeat
        matchp = cur_match

        if(zip_window[matchp + best_len+1] ~= scan_end or zip_window[matchp + best_len - 1+1] ~= scan_end1 or zip_window[matchp+1] ~= zip_window[scanp+1] or zip_window[matchp + 1+1] ~= zip_window[scanp + 1+1]) then
            continue = true
        end

        matchp = matchp + 1 -- done to combat where a ++matchp would be in the last expression

        if(not continue) then

            scanp = scanp + 2
            matchp = matchp + 1

            local function pp_scanp()
                scanp = scanp + 1
                return scanp
            end

            local function pp_matchp()
                matchp = matchp + 1
                return matchp
            end

            local function cond_check()
                return zip_window[pp_scanp()+1] == zip_window[pp_matchp()+1]
            end

            repeat
                -- do nothing
            until not (cond_check() and cond_check() and cond_check() and cond_check() and cond_check() and cond_check() and cond_check() and cond_check() and scanp < strendp)

            len = zip_MAX_MATCH - (strendp - scanp)
            scanp = strendp - zip_MAX_MATCH

            if(len > best_len) then
                zip_match_start = cur_match
                best_len = len
                if(zip_FULL_SEARCH) then
                    if(len >= zip_MAX_MATCH) then
                        break
                    end
                else
                    if(len >= zip_nice_match) then
                        break
                    end
                end
                scan_end1 = zip_window[scanp + best_len - 1+1]
                scan_end = zip_window[scanp + best_len+1]
            end

        end

        continue = false
        cur_match = zip_prev[cur_match & zip_WMASK+1]
        chain_length = chain_length - 1
    until(not (cur_match > limit and chain_length ~= 0))

    return best_len
end

function zip_fill_window()
    local n, m

    local more = zip_window_size - zip_lookahead - zip_strstart

    if(more == -1) then
        more = more - 1
    elseif(zip_strstart >= zip_WSIZE + zip_MAX_DIST) then
        for _n=0, zip_WSIZE-1, 1 do
            n=_n
            zip_window[n+1] = zip_window[n + zip_WSIZE+1]
        end

        zip_match_start = zip_match_start - zip_WSIZE
        zip_strstart = zip_strstart - zip_WSIZE
        zip_block_start = zip_block_start - zip_WSIZE

        for _n=0, zip_HASH_SIZE-1, 1 do
            n=_n
            m = zip_head1(n)
            if(m >= zip_WSIZE) then
                zip_head2(n,m-zip_WSIZE)
            else
                zip_head2(n,zip_NIL)
            end
        end

        for _n=0, zip_WSIZE - 1, 1 do
            n=_n
            m = zip_prev[n+1]
            if(m >= zip_WSIZE) then
                zip_prev[n+1] = m - zip_WSIZE
            else
                zip_prev[n+1] = zip_NIL
            end
        end

        more = more + zip_WSIZE
    end

    if(not zip_eofile) then
        n = zip_read_buff(zip_window, zip_strstart + zip_lookahead, more)
        if(n <= 0) then
            zip_eofile = true
        else
            zip_lookahead = zip_lookahead + n
        end
    end
end

function zip_deflate_fast()
    while(zip_lookahead ~= 0 and zip_qhead ~= nil) do
        local flush

        zip_INSERT_STRING()

        if(zip_hash_head ~= zip_NIL and zip_strstart - zip_hash_head <= zip_MAX_DIST) then
            zip_match_length = zip_longest_match(zip_hash_head)

            if(zip_match_length > zip_lookahead) then
                zip_match_length = zip_lookahead
            end
        end

        if(zip_match_length <= zip_MIN_MATCH) then
            flush = zip_ct_tally(zip_strstart - zip_match_start, zip_match_length - zip_MIN_MATCH)

            zip_lookahead = zip_lookahead - zip_match_length

            if(zip_match_length <= zip_max_lazy_match) then
                zip_match_length = zip_match_length-1

                repeat
                    zip_strstart = zip_strstart + 1
                    zip_INSERT_STRING()

                    zip_match_length = zip_match_length - 1
                until(not (zip_match_length ~= 0))
            else
                zip_strstart = zip_strstart + zip_match_length
                zip_match_length = 0
                zip_ins_h = zip_window[zip_strstart+1] & 0xFF

                zip_ins_h = ((zip_ins_h << zip_H_SHIFT) ~ (zip_window[zip_strstart + 1+1] & oxFF)) & zip_HASH_MASK
            end
        else
            flush = zip_ct_tally(0, zip_window[zip_strstart+1] & 0xFF)
            zip_lookahead = zip_lookahead - 1
            zip_strstart = zip_strstart + 1
        end
        if(flush) then
            zip_flush_block(0)
            zip_block_start = zip_strstart
        end

        while(zip_lookahead < zip_MIN_LOOKAHEAD and (not zip_eofile)) do
            zip_fill_window()
        end
    end
end

function zip_deflate_better()
    while(zip_lookahead ~= 0 and zip_qhead == nil) do
        zip_INSERT_STRING()
        zip_prev_length = zip_match_length
        zip_prev_match = zip_match_start
        zip_match_length = zip_MIN_MATCH-1

        if(zip_hash_head ~= zip_NIL and zip_prev_length < zip_max_lazy_match and zip_strstart - zip_hash_head <= zip_MAX_DIST) then

            zip_match_length = zip_longest_match(zip_hash_head)
            if(zip_match_length > zip_lookahead) then
                zip_match_length = zip_lookahead
            end

            if(zip_match_length == zip_MIN_MATCH and zip_strstart - zip_match_start > zip_TOO_FAR) then
                zip_match_length = zip_match_length - 1
            end

        end

        if(zip_prev_length >= zip_MIN_MATCH and zip_match_length <= zip_prev_length) then
            local flush = zip_ct_tally(zip_strstart - 1 - zip_prev_match, zip_prev_length - zip_MIN_MATCH)

            zip_lookahead = zip_lookahead - zip_prev_length - 1
            zip_prev_length = zip_prev_length - 2
            repeat
                zip_strstart = zip_strstart + 1
                zip_INSERT_STRING()

                zip_prev_length = zip_prev_length - 1
            until(not (zip_prev_length ~= 0))

            zip_match_available = 0
            zip_match_length = zip_MIN_MATCH - 1
            zip_strstart = zip_strstart + 1

            if(flush) then
                zip_flush_block(0)
                zip_block_start = zip_strstart
            end
        elseif(zip_match_available ~= 0) then
            if(zip_ct_tally(0,zip_window[zip_strstart - 1+1] & 0xFF)) then
                zip_flush_block(0)
                zip_block_start = zip_strstart
            end

            zip_strstart = zip_strstart + 1
            zip_lookahead = zip_lookahead - 1
        else
            zip_match_available = 1
            zip_strstart = zip_strstart + 1
            zip_lookahead = zip_lookahead - 1
        end
        
        while(zip_lookahead < zip_MIN_LOOKAHEAD and not zip_eofile) do
            zip_fill_window()
        end
    end
end

function zip_init_deflate()
    if(zip_eofile) then
        return
    else
        zip_bi_buf = 0
        zip_bi_valid = 0
        zip_ct_init()
        zip_lm_init()
        zip_qhead = nil
        zip_outcnt = 0
        zip_outoff = 0
        zip_match_available = 0

        if(zip_compr_level <= 3) then
            zip_prev_length = zip_MIN_MATCH - 1
            zip_match_available = 0
        else
            zip_match_length = zip_MIN_MATCH - 1
            zip_match_available = 0
        end

        zip_complete = false
    end
end

function zip_deflate_internal(buff, off, buff_size)
    local n
    if(not zip_initflag) then
        zip_init_deflate()
        zip_initflag = true
        if(zip_lookahead == 0) then
            zip_complete = 0
            return 0
        end
    end

    n = zip_qcopy(buff,off,buff_size)

    if(n == buff_size) then
        return buff_size
    end

    if(zip_complete) then
        return n
    end

    if(zip_compr_level <= 3) then
        zip_deflate_fast()
    else
        zip_deflate_better()
    end

    if(zip_lookahead == 0) then
        if(zip_match_available ~= 0) then
            zip_ct_tally(0, zip_window[zip_strstart - 1+1] & 0xFF)
        end
        zip_flush_block(1)
        zip_complete = true
    end

    return (n+ zip_qcopy(buff, n+off, buff_size - n))
end

function zip_qcopy(buff, off, buff_size)
    local n
    local i
    local j

    n = 0
    while(zip_qhead ~= nil and n < buff_size) do
        i = buff_size - n
        if(i > #zip_qhead) then
            i = #zip_qhead
        end
        for _j=0,i-1,1 do
            j=_j
            buff[off + n + j+1] = zip_qhead.ptr[zip_qhead.off + j+1]
        end

        zip_qhead.off = zip_qhead.off + 1
        zip_qhead.len = zip_qhead.len - 1

        n = n + i

        if(zip_qhead.len == 0) then
            local p
            p = zip_qhead
            zip_qhead = zip_qhead.next
            zip_reuse_queue(p)
        end
    end

    if(n == buff_size) then
        return n 
    end

    if(zip_outoff < zip_outcnt) then
        i = buff_size - n 
        if(i > zip_outcnt - zip_outoff) then
            i = zip_outcnt - zip_outoff
        end

        for _j=0,i-1,1 do
            j=_j
            buff[off + n + j+1] = zip_outbuf[zip_outoff + j+1]
        end
        zip_outoff = zip_outoff + i
        n = n + i 
        if(zip_outcnt == zip_outoff) then
            zip_outoff = 0
            zip_outcnt = zip_outoff
        end
    end
    return n
end

function zip_ct_init()
    local n, bits, length, code, dist
    if(zip_static_dtree[0+1].dl ~= 0) then
        return
    else
        zip_l_desc.dyn_tree = zip_dyn_ltree
        zip_l_desc.static_tree = zip_static_ltree
        zip_l_desc.extra_bits = zip_extra_lbits
        zip_l_desc.extra_base = zip_LITERALS + 1
        zip_l_desc.elems = zip_L_CODES
        zip_l_desc.max_length = zip_MAX_BITS
        zip_l_desc.max_code = 0

        zip_d_desc.dyn_tree = zip_dyn_dtree
        zip_d_desc.static_tree = zip_static_dtree
        zip_d_desc.extra_bits = zip_extra_dbits
        zip_d_desc.extra_base = 0
        zip_d_desc.elems = zip_D_CODES
        zip_d_desc.max_length = zip_MAX_BITS
        zip_d_desc.max_code = 0

        zip_bl_desc.dyn_tree = zip_bl_tree
        zip_bl_desc.static_tree = nil
        zip_bl_desc.extra_bits = zip_extra_blbits
        zip_bl_desc.extra_base = 0
        zip_bl_desc.elems = zip_BL_CODES
        zip_bl_desc.max_length = zip_MAX_BL_BITS
        zip_bl_desc.max_code = 0

        length = 0

        for _code=0,zip_LENGTH_CODES-2,1 do
            code=_code
            zip_base_length[code+1] = length
            for _n=0,(1 << zip_extra_lbits[code+1]) - 1,1 do
                n=_n
                zip_length_code[length+1] = code
                length = length + 1
            end
        end

        zip_length_code[length-1+1] = code

        dist = 0
        for _code=0,15,1 do
            code=_code
            zip_base_dist[code+1] = dist
            for _n=0,(1<<zip_extra_dbits[code+1])-1,1 do
                n=_n
                zip_dist_code[dist+1] = code
                dist = dist + 1
            end
        end

        dist = dist >> 7
        for _code=code,zip_D_CODES-1,1 do
            code=_code
            zip_base_dist[code+1] = dist << 7
            for _n=0,(1<<(zip_extra_dbits[code+1]-7))-1,1 do
                n=_n
                zip_dist_code[256 + dist+1] = code
                dist = dist + 1
            end
        end
        
        for _bits=0,zip_MAX_BITS,1 do
            bits=_bits
            zip_bl_count[bits+1] = 0
        end

        n = 0

        while(n <= 143) do
            zip_static_ltree[n+1].dl = 8
            n = n + 1
            zip_bl_count[8+1] = zip_bl_count[8+1] + 1
        end
        while(n <= 255) do
            zip_static_ltree[n+1].dl = 9
            n = n + 1
            zip_bl_count[9+1] = zip_bl_count[9+1] + 1
        end
        while(n <= 279) do
            zip_static_ltree[n+1].dl = 7
            n = n + 1
            zip_bl_count[7+1] = zip_bl_count[7+1] + 1
        end
        while(n <= 287) do
            zip_static_ltree[n+1].dl = 8
            n = n + 1
            zip_bl_count[8+1] = zip_bl_count[8+1] + 1
        end

        zip_gen_codes(zip_static_ltree, zip_L_CODES + 1)

        for _n=0,zip_D_CODES-1,1 do
            n=_n
            zip_static_dtree[n+1].dl = 5
            zip_static_dtree[n+1].fc = zip_bi_reverse(n, 5)
        end

        zip_init_block()
    end
end

function zip_init_block()
    local n

    for _n=0,zip_L_CODES-1,1 do
        n=_n
        zip_dyn_ltree[n+1].fc = 0
    end
    for _n=0,zip_D_CODES-1,1 do
        n=_n
        zip_dyn_dtree[n+1].fc = 0
    end
    for _n=0,zip_BL_CODES-1,1 do
        n=_n
        zip_bl_tree[n+1].fc = 0
    end

    zip_dyn_ltree[zip_END_BLOCK+1].fc = 1
    zip_static_len = 0
    zip_opt_len = zip_static_len
    zip_last_flags = 0
    zip_last_dist = zip_last_flags
    zip_last_lit = zip_last_dist
    zip_flags = 0
    zip_flag_bit = 1
end

function zip_pqdownheap(tree, k)
    local v = zip_heap[k+1]
    local j = k << 1

    while(j <= zip_heap_len) do
        if(j< zip_heap_len and zip_SMALLER(tree, zip_heap[j+1+1],zip_heap[j+1])) then
            j = j + 1
        end

        if(zip_SMALLER(tree,v,zip_heap[j+1])) then
            break
        end

        zip_heap[k+1] = zip_heap[j+1]
        k = j

        j = j << 1
    end
    zip_heap[k+1] = v 
end

function zip_gen_bitlen(desc)
    local tree = desc.dyn_tree
    local extra = desc.extra_bits
    local base = desc.extra_base
    local max_code = desc.max_code
    local max_length = desc.max_length
    local stree = desc.static_tree
    local h,n,m,bits,xbits,f
    local overflow = 0
    local continue = false
    local continue2 = false

    for _bits=0,zip_MAX_BITS,1 do
        bits=_bits
        zip_bl_count[bits+1] = 0
    end

    tree[zip_heap[zip_heap_max+1]+1].dl = 0

    for _h=zip_heap_max+1,zip_HEAP_SIZE-1,1 do
        h=_h
        n = zip_heap[h+1]
        bits = tree[tree[n+1].dl+1].dl + 1
        if(bits > max_length) then
            bits = max_length
            overflow = overflow + 1
        end
        tree[n+1].dl = bits

        if(n > max_code) then
            continue = true
        end

        if not continue then
            zip_bl_count[bits+1] = zip_bl_count[bits+1] + 1
            xbits = 0
            if(n >= base) then
                xbits = extra[n - base+1]
            end
            f = tree[n+1].fc
            zip_opt_len = zip_opt_len + (f * (bits + xbits))
            if(stree ~= nil) then
                zip_static_len = zip_static_len + (f * (stree[n+1].dl + xbits))
            end
        end
    end
    if(overflow == 0) then
        return
    else
        repeat
            bits = max_length - 1
            while(zip_bl_count[bits+1] == 0) do
                bits = bits - 1
            end
            zip_bl_count[bits+1] = zip_bl_count[bits+1] - 1
            zip_bl_count[bits + 1+1] = zip_bl_count[bits + 1+1] + 2
            zip_bl_count[max_length+1] = zip_bl_count[max_length+1] - 1
            overflow = overflow - 2
        until(not (overflow > 0))

        for _bits=max_length,1,-1 do
            bits=_bits
            n = zip_bl_count[bits+1]
            while(n ~= 0) do
                h = h - 1
                m = zip_heap[h+1]
                if(m > max_code) then
                    continue2 = true
                end
                if(not continue2) then
                    if(tree[m+1].dl ~= bits) then
                        zip_opt_len = zip_opt_len + ((bits - tree[m+1].dl) * tree[m+1].fc)
                        tree[m+1].fc = bits;
                    end
                    n = n - 1
                end
            end
        end
    end
end

function zip_gen_codes(tree, max_code)
    local next_code = Array(zip_MAX_BITS+1)
    local code = 0
    local bits, n

    for _bits=1,zip_MAX_BITS,1 do
        bits=_bits
        code = ((code + zip_bl_count[bits-1+1]) << 1)
        next_code[bits+1] = code
    end

    for _n=0,max_code,1 do
        n=_n
        local len = tree[n+1].dl
        if not (len == 0) then
            tree[n+1].fc = zip_bi_reverse(next_code[len+1], len)
            next_code[len+1] = next_code[len+1]+1
        end
    end
end

function zip_build_tree(desc)
    local tree = desc.dyn_tree
    local stree = desc.static_tree
    local elems = desc.elems
    local n,m
    local max_code = -1
    local node = elems

    zip_heap_len = 0
    zip_heap_max = zip_HEAP_SIZE

    for _n=0,elems-1,1 do
        n=_n
        if(tree[n+1].fc ~= 0) then
            max_code = n
            zip_heap_len = zip_heap_len + 1
            zip_heap[zip_heap_len+1] = max_code
            zip_depth[n+1] = 0
        else
            tree[n+1].dl = 0
        end
    end

    while(zip_heap_len < 2) do
        local xnew = 0
        if(max_code < 2) then
            max_code = max_code + 1
            xnew = max_code
        end
        zip_heap_len = zip_heap_len + 1
        zip_heap[zip_heap_len+1] = xnew
        tree[xnew+1].fc = 1
        zip_depth[xnew+1] = 0
        zip_opt_len = zip_opt_len - 1
        if(stree ~= nil) then
            zip_static_len = zip_static_len - (stree[xnew+1].dl)
        end
    end

    desc.max_code = max_code

    for _n=(zip_heap_len >> 1),1,-1 do
        n=_n
        zip_pqdownheap(tree, n)
    end

    repeat
        n = zip_heap[zip_SMALLEST+1]
        zip_heap[zip_SMALLEST+1] = zip_heap[zip_heap_len+1]
        zip_heap_len = zip_heap_len - 1
        zip_pqdownheap(tree,zip_SMALLEST)

        m = zip_heap[zip_SMALLEST+1]

        zip_heap_max = zip_heap_max - 1
        zip_heap[zip_heap_max+1] = n
        zip_heap_max = zip_heap_max - 1
        zip_heap[zip_heap_max+1] = m

        tree[node+1].fc = tree[n+1].fc + tree[m+1].fc

        if(zip_depth[n+1] > zip_depth[m+1] + 1) then
            zip_depth[node+1] = zip_depth[n+1]
        else
            zip_depth[node+1] = zip_depth[m+1] + 1
        end
        tree[m+1].dl = node
        tree[n+1].dl = tree[m+1].dl
        zip_heap[zip_SMALLEST+1] = node
        node = node + 1
        zip_pqdownheap(tree, zip_SMALLEST)
    until not (zip_heap_len >= 2)

    zip_heap_max = zip_heap_max - 1
    zip_heap[zip_heap_max+1] = zip_heap[zip_SMALLEST+1]

    zip_gen_bitlen(desc)

    zip_gen_codes(tree, max_code)
end

function zip_scan_tree(tree,max_code)
    local n
    local prevlen = -1
    local curlen
    local nextlen = tree[0+1].dl
    local count = 0
    local max_count = 7
    local min_count = 4

    if(nextlen == 0) then
        max_count = 138
        min_count = 3
    end
    tree[max_code + 1+1].dl = 0xFFFF

    for _n=0,max_code,1 do
        n=_n
        local continue = false
        curlen = nextlen
        nextlen = tree[n+1+1].dl
        count = count + 1
        if(count < max_count and curlen == nextlen) then
            continue = true
        elseif(count < min_count) then
            zip_bl_tree[curlen+1].fc = zip_bl_tree[curlen+1].fc + count
        elseif(curlen ~= 0) then
            if(curlen ~= prevlen) then
                zip_bl_tree[curlen+1].fc = zip_bl_tree[curlen+1].fc + 1
            end
            zip_bl_tree[zip_REP_3_6+1].fc = zip_bl_tree[zip_REP_3_6+1].fc + 1
        elseif(count <= 10) then
            zip_bl_tree[zip_REPZ_3_10+1].fc = zip_bl_tree[zip_REPZ_3_10+1].fc + 1
        else
            zip_bl_tree[zip_REPZ_11_138+1].fc = zip_bl_tree[zip_REPZ_11_138+1].fc + 1
        end
        if(not continue) then
            count = 0
            prevlen = curlen
            if(nextlen == 0) then
                max_count = 138
                min_count = 3
            elseif(curlen == nextlen) then
                max_count = 6
                min_count = 3
            else
                max_count = 7
                min_count = 4
            end
        end
    end
end

function zip_send_tree(tree, max_code)
    local n
    local prevlen = -1
    local curlen
    local nextlen = tree[0+1].dl
    local count = 0
    local max_count = 7
    local min_count = 4

    if(nextlen == 0) then
        max_count = 128
        min_count = 3
    end

    for _n=0,max_code,1 do
        n=_n
        local continue = false
        curlen = nextlen
        nextlen = tree[n+1+1].dl
        count = count + 1
        if(count < max_count and curlen == nextlen) then
            continue = true
        elseif(count < min_count) then
            local function mmcount()
                count = count - 1
                return count
            end
            repeat
                zip_SEND_CODE(curlen, zip_bl_tree)
            until not (mmcount() ~= 0)
        elseif(curlen ~= 0) then
            if(curlen ~= prevlen) then
                zip_SEND_CODE(curlen,zip_bl_tree)
                count = count - 1
            end

            zip_SEND_CODE(zip_REP_3_6, zip_bl_tree)
            zip_send_bits(count - 3, 2)
        elseif(count <= 10) then
            zip_SEND_CODE(zip_REPZ_3_10, zip_bl_tree)
            zip_send_bits(count-3, 3)
        else
            zip_SEND_CODE(zip_REPZ_11_138, zip_bl_tree)
            zip_send_bits(count-11, 7)
        end

        if not continue then
            count = 0
            prevlen = curlen
            if(nextlen == 0) then
                max_count = 138
                min_count = 3
            elseif(curlen == nextlen) then
                max_count = 6
                min_count = 3
            else
                max_count = 7
                min_count = 4
            end
        end
    end
end

function zip_build_bl_tree()
    local max_blindex

    zip_scan_tree(zip_dyn_ltree, zip_l_desc.max_code)
    zip_scan_tree(zip_dyn_dtree, zip_d_desc.max_code)
    zip_build_tree(zip_bl_desc)

    for _max_blindex=zip_BL_CODES-1,3,-1 do
        max_blindex=_max_blindex
        if(zip_bl_tree[zip_bl_order[max_blindex+1]+1].dl ~= 0) then
            break
        end
    end

    zip_opt_len = zip_opt_len + (3*(max_blindex+1) + 5+5+4)

    return max_blindex
end

function zip_send_all_trees(lcodes, dcodes, blcodes)
    local rank
    zip_send_bits(lcodes-257, 5)
    zip_send_bits(dcodes-1,   5)
    zip_send_bits(blcodes-4,  4)
    for _rank=0,blcodes-1,1 do
        rank=_rank
        zip_send_bits(zip_bl_tree[zip_bl_order[rank+1]+1].dl, 3)
    end

    zip_send_tree(zip_dyn_ltree,lcodes-1)
    zip_send_tree(zip_dyn_dtree,dcodes-1)
end

function zip_flush_block(eof)
    local opt_lenb, static_lenb, max_blindex, stored_len

    stored_len = zip_strstart - zip_block_start
    zip_flag_buf[zip_last_flags+1] = zip_flags

    zip_build_tree(zip_l_desc)
    zip_build_tree(zip_d_desc)

    max_blindex = zip_build_bl_tree()

    opt_lenb = (zip_opt_len+3+7) >> 3
    static_lenb = (zip_static_len+3+7) >> 3

    if(static_lenb <= opt_lenb) then
        opt_lenb = static_lenb
    end

    if(stored_len + 4 <= opt_lenb and zip_block_start >= 0) then
        local i
        zip_send_bits((zip_STORED_BLOCK<<1)+eof, 3)
        zip_bi_windup()
        zip_put_short(stored_len)
        zip_put_short(~stored_len)

        for _i=0,stored_len-1,1 do 
            i=_i
            zip_put_byte(zip_window[zip_block_start + i+1])
        end
    elseif(static_lenb == opt_lenb) then
        zip_send_bits((zip_STATIC_TREES<<1)+eof, 3)
        zip_compress_block(zip_static_ltree, zip_static_dtree)
    else
        zip_send_bits((zip_DYN_TREES<<1)+eof, 3)
        zip_send_all_trees(zip_l_desc.max_code+1, zip_d_desc.max_code+1, max_blindex+1)
        zip_compress_block(zip_dyn_ltree, zip_dyn_dtree)
    end

    zip_init_block()

    if(eof ~= 0) then
        zip_bi_windup()
    end
end

local function int(x)
    if type(x) == "number" then
        return math.floor(x)
    else
        return math.floor(tonumber(x))
    end
end

function zip_ct_tally(dist,lc)
    zip_l_buf[zip_last_lit+1] = lc
    zip_last_lit = zip_last_lit + 1
    if(dist == 0) then
        zip_dyn_ltree[lc+1].fc = zip_dyn_ltree[lc+1].fc + 1
    else
        dist = dist - 1
        zip_dyn_ltree[zip_length_code[lc+1]+zip_LITERALS+1+1].fc = zip_dyn_ltree[zip_length_code[lc+1]+zip_LITERALS+1+1].fc + 1
        zip_dyn_dtree[zip_D_CODE(dist)+1].fc = zip_dyn_dtree[zip_D_CODE(dist)+1].fc + 1
        zip_d_buf[zip_last_dist+1] = dist
        zip_last_dist = zip_last_dist + 1
        zip_flags = zip_flags | zip_flag_bit
    end

    zip_flag_bit = zip_flag_bit << 1

    if((zip_last_lit & 7) == 0) then
        zip_flag_buf[zip_last_flags+1] = zip_flags
        zip_last_flags = zip_last_flags + 1
        zip_flags = 0
        zip_flag_bit = 1
    end

    if(zip_compr_level > 2 and ((zip_last_lit & 0xFFF) == 0)) then
        local out_length = zip_last_lit * 8
        local in_length = zip_strstart - zip_block_start
        local dcode

        for _dcode=0, zip_D_CODES-1, 1 do
            dcode=_dcode
            out_length = out_length + (zip_dyn_dtree[dcode+1].fc * (5 + zip_extra_dbits[dcode+1]))
        end

        out_length = out_length >> 3

        if(zip_last_dist < int(zip_last_lit/2) and out_length < int(in_length/2)) then
            return true
        end
    end

    return (zip_last_lit == zip_LIT_BUFSIZE-1 or zip_last_dist == zip_DIST_BUFSIZE)
end

function zip_compress_block(ltree, dtree)
    local dist, lc
    local lx = 0
    local dx = 0
    local fx = 0
    local flag = 0
    local code, extra

    if(zip_last_lit ~= 0) then
        repeat
            if((lx & 7) == 0) then
                flag = zip_flag_buf[fx+1]
                fx = fx + 1
            end
            lc = zip_l_buf[lx+1] & 0xff
            lx = lx + 1
            if((flag & 1) == 0) then
                zip_SEND_CODE(lc, ltree)
            else
                code = zip_length_code[lc+1]
                zip_SEND_CODE(code+zip_LITERALS+1, ltree)
                extra = zip_extra_lbits[code+1]
                if(extra ~= 0) then
                    lc = lc - zip_base_length[code+1]
                    zip_send_bits(lc, extra)
                end

                dist = zip_d_buf[dx+1]
                dx = dx + 1

                code = zip_D_CODE(dist)

                zip_SEND_CODE(code, dtree)
                extra = zip_extra_dbits[code+1]
                if(extra ~= 0) then
                    dist = dist - zip_base_dist[code+1]
                    zip_send_bits(dist, extra)
                end
            end

            flag = flag >> 1
        until not (lx < zip_last_lit)
    end

    zip_SEND_CODE(zip_END_BLOCK, ltree)
end

function zip_send_bits(value, length)
    if(zip_bi_valid > zip_Buf_size - length) then
        zip_bi_buf = zip_bi_buf | (value << zip_bi_valid)
        zip_put_short(zip_bi_buf)
        zip_bi_buf = (value >> (zip_Buf_size - zip_bi_valid))
        zip_bi_valid = zip_bi_valid + (length - zip_Buf_size)
    else
        zip_bi_buf = zip_bi_buf | (value << zip_bi_valid)
        zip_bi_valid = zip_bi_valid + length
    end
end

function zip_bi_reverse(code,len)

    local function mmlen()
        len = len - 1
        return len
    end

    local res = 0
    repeat
        res = res | (code & 1)
        code = code >> 1
        res = res << 1
    until not (mmlen() > 0)

    return res >> 1
end

function zip_bi_windup()
    if(zip_bi_valid > 8) then
        zip_put_short(zip_bi_buf)
    elseif(zip_bi_valid > 0) then
        zip_put_byte(zip_bi_buf)
    end

    zip_bi_buf = 0
    zip_bi_valid = 0
end

function zip_qoutbuf()
    if(zip_outcnt ~= 0) then
        local q, i
        q = zip_new_queue()
        if(zip_qhead == nil) then
            zip_qtail = q
            zip_qhead = zip_qtail
        else
            zip_qtail.next = q
            zip_qtail = zip_qtail.next
        end

        q.len = zip_outcnt - zip_outoff
        for _i=0,q.len-1,1 do
            i=_i
            q.ptr[i+1] = zip_outbuf[zip_outoff + i+1]
        end

        zip_outoff = 0
        zip_outcnt = zip_outoff
    end
end

function zip_deflate(str,level)
    local i,j

    zip_deflate_data = str
    zip_deflate_pos = 0

    if(level == nil) then
        level = zip_DEFAULT_LEVEL
    end

    zip_deflate_start(level)
    local buff = Array(1024)
    local aout = {}
    local function cond()
        i = zip_deflate_internal(buff, 0, #buff)
        return i > 0
    end
    while(cond()) do
        local cbuf = {}
        local h = 1
        for _j=0,i-1,1 do
            j=_j
            if(j%3 ~= 0 and j ~= 0) then -- if i dont do this then the algorithm doesnt work correctly.
                cbuf[h] = string.char(buff[j+1])
                h = h+1
            end
        end
        aout[#aout+1] = table.concat(cbuf,"")
    end

    zip_deflate_data = nil
    return table.concat(aout,"")
end