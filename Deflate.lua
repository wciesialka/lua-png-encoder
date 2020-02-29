local function Array(n) -- function to create a table with a preset length, like a C-style array
    local t = {}
    for i=0,n-1,1 do
        t[i] = nil
    end
    return t
end

local function Array_Function(n,f,...)
    local t = {}
    for i=0,n-1,1 do
        t[i]=f(...)
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
    return zip_prev[zip_WSIZE + i]
end

function zip_head2(i, val)
    zip_prev[zip_WSIZE + i] = val
    return zip_prev[zip_WSIZE + i]
end

function zip_put_byte(c)
    zip_outcnt = zip_outcnt + 1
    zip_outbuf[zip_outoff + zip_outcnt] = c
    if(zip_outoff + zip_outcnt == zip_OUTBUFSIZ) then
        zip_qoutbuf()
    end
end

function zip_put_short(w)
    w = w & 0xFFFF
    if(zip_outoff + zip_outcnt < zip_OUTBUFSIZ - 2) then
        zip_outcnt = zip_outcnt + 1
        zip_outbuf[zip_outoff + zip_outcnt] = (w & 0xFF)
        zip_outcnt = zip_outcnt + 1
        zip_outbuf[zip_outoff + zip_outcnt++] = (w >> 8)
    else
        zip_put_byte(w & 0xff)
        zip_put_byte(w >> 8)
    end
end

-- Insert string s in the dictionary and set match_head to the previous head
-- of the hash chain (the most recent string with same hash key). Return
-- the previous length of the hash chain.
function zip_INSERT_STRING()
    zip_ins_h = ((zip_ins_h << zip_H_SHIFT) ^ (zip_window[zip_strstart + zip_MIN_MATCH - 1] & 0xff)) & zip_HASH_MASK
    zip_hash_head = zip_head1(zip_ins_h)
    zip_prev[zip_strstart & zip_WMASK] = zip_hash_head
    zip_head2(zip_ins_h, zip_strstart)
end

function zip_SEND_CODE(c, tree)
    zip_send_bits(tree[c].fc, tree[c].dl)
end

function zip_D_CODE(dist)
    if(dist < 256) then
        return zip_dist_code[dist] & 0xFF
    else
        return zip_dist_code[256+(dist >> 7)] & 0xFF
    end
end

function zip_SMALLER(tree, n, m)
    return (tree[n].fc < tree[m].fc) || (tree[n].fc == tree[m].fc && zip_depth[n] <= zip_depth[m])
end

function zip_read_buff(buff, offset, n)
    local i = 0
    while(i < n && zip_deflate_pos < #zip_deflate_data) do
        zip_deflate_pos = zip_deflate_pos + 1
        buff[offset + i] = utf8.codepoint(zip_deflate_data,zip_deflate_pos,zip_deflate_pos) & 0xFF
        i = i+1
    end

    return i
end

function zip_lm_init()
    local j

    for j=0,zip_HASH_SIZE-1,1 do
        zip_prev[zip_WSIZE + j] = 0
    end

    zip_max_lazy_match = zip_configuration_table[zip_compr_level].max_lazy
    zip_good_match = zip_configuration_table[zip_compr_level].good_length
    if(not zip_FULL_SEARCH) then
        zip_nice_match = zip_configuration_table[zip_compr_level].nice_length
    end

    zip_max_chain_length = zip_configuration_table[zip_compr_level].max_chain

    zip_strstart = 0
    zip_block_start = 0

    zip_lookahead = zip_read_buff(zip_window, 0, 2 * zip_WSIZE)
    if(zip_lookahead <= 0) then
        zip_eofile = true
        zip_lookahead = 0
        return
    end

    zip_eofile = false

    while(zip_lookahead < zip_MIN_LOOKAHEAD and (not zip_eofile)) then
        zip_fill_window()
    end

    zip_ins_h = 0
    for j=0,zip_MIN_MATCH - 2, 1 do
        zip_ins_h = ((zip_ins_h << zip_H_SHIFT) ~ (zip_window[j] & 0xFF))
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
    local scan_end1 = zip_window[scanp + best_len- 1]
    local scan_end = zip_window[scanp + best_len]

    local continue = false

    if(zip_prev_length >= zip_good_match) then
        chain_length = chain_length >> 2
    end

    repeat
        matchp = cur_match

        if(zip_window[matchp + best_len] ~= scan_end or zip_window[matchp + best_len - 1] ~= scan_end1 or zip_window[matchp] ~= zip_window[scanp] or zip_window[matchp + 1] ~= zip_window[scanp + 1]) then
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
                return zip_window[pp_scanp()] == zip_window[pp_matchp()]
            end

            do

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
                scan_end1 = zip_window[scanp + best_len - 1]
                scan_end = zip_window[scanp + best_len]
            end

        end

        continue = false
        cur_match = zip_prev[cur_match & zip_WMASK]
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
        for n=0, zip_WSIZE-1, 1 do
            zip_window[n] = zip_window[n + zip_WSIZE]
        end

        zip_match_start = zip_match_start - zip_WSIZE
        zip_strstart = zip_strstart - zip_WSIZE
        zip_block_start = zip_block_start - zip_WSIZE

        for n=0, zip_HASH_SIZE-1, 1 do
            m = zip_head1(n)
            if(m >= zip_WSIZE) then
                zip_head2(n,m-zip_WSIZE)
            else
                zip_head2(n,zip_NIL)
            end
        end

        for n=0, zip_WSIZE - 1, 1 do
            m = zip_prev[n]
            if(m >= zip_WSIZE) then
                zip_prev[n] = m - zip_WSIZE
            else
                zip_prev[n] = zip_NIL
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
                zip_ins_h = zip_window[zip_strstart] & 0xFF

                zip_ins_h = ((zip_ins_h << zip_H_SHIFT) ~ (zip_window[zip_strstart + 1] & oxFF)) & zip_HASH_MASK
            end
        else
            flush = zip_ct_tally(0, zip_window[zip_strstart] & 0xFF)
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
            do
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
            if(zip_ct_tally(0,zip_window[zip_strstart - 1] & 0xFF)) then
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
            zip_ct_tally(0, zip_window[zip_strstart - 1] & 0xFF)
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
    while(zip_qhead != nil and n < buff_size) do
        i = buff_size - n
        if(i > #zip_qhead) then
            i = #zip_qhead
        end
        for j=0,i-1,1 do
            buff[off + n + j] = zip_qhead.ptr[zip_qhead.off + j]
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

        for j=0,i-1,1 do
            buff[off + n + j] = zip_outbuf[zip_outoff + j]
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

