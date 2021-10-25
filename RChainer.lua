function printChain(pre, u)
    if u.offset == nil then
        return u.value
    else
        local ret = ''
        for offset, v in pairs(u.offset) do
            table.insert(l_table_down2, offset)
            ret = ret .. '\n\n' ..
                      printChain(
                          pre ..
                              string.format(' -> 0x%X + 0x%X', u.value, offset),
                          v)
        end
        if ret ~= '' then ret = ret:sub(3) end
        return ret
    end
end

function S_Pointer(t_So, t_Offset, _bit)
    local function getRanges()
        local ranges = {}
        local t = gg.getRangesList('^/data/*.so*$')
        for i, v in pairs(t) do
            if v.type:sub(2, 2) == 'w' then table.insert(ranges, v) end
        end
        return ranges
    end
    local function Get_Address(N_So, Offset, ti_bit)
        local ti = gg.getTargetInfo()
        local S_list = getRanges()
        local t = {}
        local _t
        local _S = nil
        if ti_bit then
            _t = 32
        else
            _t = 4
        end
        for i in pairs(S_list) do
            local _N = S_list[i].internalName:gsub('^.*/', '')
            if N_So[1] == _N and N_So[2] == S_list[i].state then
                _S = S_list[i]
                break
            end
        end
        if _S then
            t[#t + 1] = {}
            t[#t].address = _S.start + Offset[1]
            t[#t].flags = _t
            if #Offset ~= 1 then
                for i = 2, #Offset do
                    local S = gg.getValues(t)
                    t = {}
                    for _ in pairs(S) do
                        if not ti.x64 then
                            S[_].value = S[_].value & 0xFFFFFFFF
                        end
                        t[#t + 1] = {}
                        t[#t].address = S[_].value + Offset[i]
                        t[#t].flags = _t
                    end
                end
            end
            _S = t[#t].address
        end
        return _S
    end
    local _A = string.format('0x%X', Get_Address(t_So, t_Offset, _bit))
    return _A
end

local ti = gg.getTargetInfo()
local x64 = ti.x64

if gg.getResultsCount() ~= 1 then
    print('当前搜索列表不为1')
    os.exit()
end

local ac_ = gg.getResults(1)[1]
local ac_flags = ac_.flags
local ac_value = ac_.value

local depth, minOffset, maxOffset, level, out

function loadChain(lvl, p)
    local fix, mino, maxo, lev = not x64, minOffset, maxOffset, level
    for k = lvl, 1, -1 do
        local levk, p2, stop = lev[k], {}, true
        for j, u in pairs(p) do
            if u.offset == nil then
                u.offset = {}
                if fix then u.value = u.value & 0xFFFFFFFF end
                for i, v in ipairs(levk) do
                    local offset = v.address - u.value
                    if offset >= mino and offset <= maxo then
                        u.offset[offset], p2[v], stop = v, v, false
                    end
                end
            end
        end
        if stop then break end
        p = p2
    end
end

function getRanges()
    local archs = {
        [0x3] = 'x86',
        [0x28] = 'ARM',
        [0x3E] = 'x86-64',
        [0xB7] = 'AArch64'
    }
    local ranges = {}
    local t = gg.getRangesList('^/data/*.so*$')
    local arch = 'unknown'
    for i, v in ipairs(t) do
        if v.type:sub(2, 2) == '-' then
            local t = gg.getValues({
                {address = v.start, flags = gg.TYPE_DWORD},
                {address = v.start + 0x12, flags = gg.TYPE_WORD}
            })
            if t[1].value == 0x464C457F then
                arch = archs[t[2].value]
                if arch == nil then arch = 'unknown' end
            end
        end
        if v.type:sub(2, 2) == 'w' then
            v.arch = arch
            table.insert(ranges, v)
        end
    end
    return ranges
end

local ranges = getRanges()

gg.setRanges(gg.REGION_C_HEAP | gg.REGION_C_ALLOC | gg.REGION_C_DATA |
                 gg.REGION_C_BSS | gg.REGION_ANONYMOUS)

local cfg_file = gg.getFile() .. '.cfg'
local chunk = loadfile(cfg_file)
local cfg = nil
if chunk ~= nil then cfg = chunk() end
if cfg == nil then cfg = {} end

local pkg = gg.getTargetPackage()
if pkg == nil then pkg = 'none' end

gg.setVisible(false)
while true do
    local def = cfg[pkg]
    if def == nil then def = {3, 0, 256} end
    local p = gg.prompt({'深度', '最小偏移量', '最大偏移量'}, def,
                        {'number', 'number', 'number'})

    if p == nil then
        gg.setVisible(true)
        os.exit()
    end
    cfg[pkg] = p
    gg.saveVariable(cfg, cfg_file)

    depth = p[1]
    minOffset = tonumber(p[2])
    maxOffset = tonumber(p[3])

    level, out = {}, {}

    local old = gg.getResults(100000)
    local x = os.clock()

    for lvl = 0, depth do
        if lvl > 0 then
            local t = gg.getResults(100000)
            level[lvl] = t
            gg.toast(lvl .. ' from ' .. depth)
            gg.internal3(maxOffset)
        end

        for m, r in ipairs(ranges) do
            local p = gg.getResults(100000, 0, r.start, r['end'])
            if #p > 0 then
                gg.removeResults(p)
                loadChain(lvl, p)
                p.map = r
                table.insert(out, p)
            end
        end

        if gg.getResultsCount() == 0 then break end
    end

    gg.loadResults(old)

    -- 入表
    t_table = {}
    for j, p in ipairs(out) do
        for i, u in ipairs(p) do
            local l_table_down1 = {}
            table.insert(t_table, l_table_down1)
            table.insert(l_table_down1, string.format('%s',
                                                      p.map.internalName:gsub(
                                                          '^.*/', '')))
            table.insert(l_table_down1, string.format('%s', p.map.state))

            l_table_down2 = {}
            table.insert(t_table, l_table_down2)
            table.insert(l_table_down2, u.address - p.map.start)
            printChain(string.format('%s + 0x%X [0x%X]',
                                     p.map.internalName:gsub('^.*/', ''),
                                     u.address - p.map.start, u.address), u)
        end
    end

    gg.toast("正在校验" .. #t_table .. "条链路，请稍候")
    -- 检验
    last_table = {}
    for i = 1, #t_table, 2 do
        local t = t_table[i]
        local tt = t_table[i + 1]
        local ttt = S_Pointer(t, tt, true)
        if gg.getValues({{address = ttt, flags = ac_flags}})[1].value ==
            ac_value then
            table.insert(last_table, t)
            table.insert(last_table, tt)
            gg.toast("第" .. string.format('%s', (i + 1) / 2) ..
                         "条链路可用")
        end
    end

    local chain = ''
    if #last_table == 0 then chain = '\n\n没有结果' end
    gg.toast("已找到" .. #last_table .. "条链路")
    -- 重现链路

    for i = 1, #last_table, 2 do
        chain = chain .. "\n\n" .. string.format('%s', (i + 1) / 2) .. ":" ..
                    string.format('%s', last_table[i][1]) .. " + " ..
                    string.format('0x%X', last_table[i + 1][1])
        for j = 2, #last_table[i + 1] do
            chain = chain .. string.format(' -> 0x%X', last_table[i + 1][j])
        end
        chain = chain .. " = " .. string.format('%s', ac_value)
    end

    x = string.format('%.2f', os.clock() - x)
    print(depth, minOffset, maxOffset, x)

    local chains = #last_table / 2
    p = gg.alert('在' .. x .. '秒内找到了' .. chains .. '条链路 (' ..
                     depth .. ', ' .. minOffset .. ', ' .. maxOffset .. '):' ..
                     chain, '保存', '重试', '退出')
    if p == 1 then break end
    if p ~= 2 then
        print(last_table)
        print(chain)
        gg.setVisible(true)
        os.exit()

    end
end

function main(last_table, ac_flags, ac_value, control_str)
    for i = 1, #last_table do
        local t = last_table[i][1]
        local tt = last_table[i][2]
        local ttt = S_Pointer(t, tt, true)
        if control_str == "==" then
            if gg.getValues({{address = ttt, flags = ac_flags}})[1].value ==
                ac_value then
                control_flag = true
                gg.searchNumber(ac_value, ac_flags, false, gg.SIGN_EQUAL, ttt,
                                ttt)
            end
        elseif control_str == "~=" then
            if gg.getValues({{address = ttt, flags = ac_flags}})[1].value ~=
                ac_value then
                control_flag = true
                gg.searchNumber(ac_value, ac_flags, false, gg.SIGN_NOT_EQUAL,
                                ttt, ttt)
            end
        elseif control_str == ">" then
            if gg.getValues({{address = ttt, flags = ac_flags}})[1].value >
                ac_value then
                control_flag = true
                gg.searchNumber(ac_value, ac_flags, false,
                                gg.SIGN_GREATER_OR_EQUAL, ttt, ttt)
            end
        elseif control_str == ">=" then
            if gg.getValues({{address = ttt, flags = ac_flags}})[1].value >=
                ac_value then
                control_flag = true
                gg.searchNumber(ac_value, ac_flags, false,
                                gg.SIGN_GREATER_OR_EQUAL, ttt, ttt)
            end
        elseif control_str == "<" then
            if gg.getValues({{address = ttt, flags = ac_flags}})[1].value <
                ac_value then
                control_flag = true
                gg.searchNumber(ac_value, ac_flags, false,
                                gg.SIGN_LESS_OR_EQUAL, ttt, ttt)
            end
        elseif control_str == "<=" then
            if gg.getValues({{address = ttt, flags = ac_flags}})[1].value <=
                ac_value then
                control_flag = true
                gg.searchNumber(ac_value, ac_flags, false,
                                gg.SIGN_LESS_OR_EQUAL, ttt, ttt)
            end
        end
        if control_flag then
            li_str = "\n{{"
            for l, m in ipairs(t) do
                li_str = li_str .. "'" .. string.format('%s', m) .. "',"
            end
            li_str = li_str .. "},{"
            for l, m in ipairs(tt) do
                li_str = li_str .. string.format('0x%X', m) .. ","
            end
            li_str = li_str .. "}}\n\n"
            print("序号: " .. i)
            print(gg.getValues({{address = ttt, flags = ac_flags}})[1])
            print(li_str)
        end
    end
end

-- 文件名
local script = gg.getFile():gsub('[^/]*$', '') .. ti.packageName
for i = 1, 1000 do
    local f = io.open(script .. i .. "-" .. string.format('%s', depth) .. "-" ..
                          string.format('%s', minOffset) .. "-" ..
                          string.format('%s', maxOffset) .. '.lua')
    if f == nil then
        script = script .. i .. "-" .. string.format('%s', depth) .. "-" ..
                     string.format('%s', minOffset) .. "-" ..
                     string.format('%s', maxOffset) .. '.lua';
        break
    end
    f:close()
end

function Con_choise()
    local control_str_T = {"==", "~=", ">", ">=", "<", "<="}
    local control_str_num = gg.choice(control_str_T, 1,
                                      "选择合适的判断条件，取消则选取默认值")
    if control_str_num == nil then control_str_num = 1 end
    local control_str = control_str_T[control_str_num]
    ac_value_S = gg.prompt({
        "当前判断条件为: " .. string.format('%s', control_str) ..
            "\n当前默认值为: " .. string.format('%s', ac_value) ..
            "\n请输入合适的判断值，取消则返回上一步"
    }, {[1] = ac_value}, {[1] = "number"})
    if ac_value_S == nil or ac_value_S[1] == "" then Con_choise() end
    ac_value = tonumber(ac_value_S[1])
    return control_str, ac_value
end
local control_str, ac_value = Con_choise()

local p = gg.prompt({'输出文件'}, {script}, {'file'})
if p ~= nil then
    script = p[1]

    code = ''

    local cpi = {}
    for i, u in ipairs({S_Pointer, main}) do cpi[i] = debug.getinfo(u) end
    local n = 0
    for line in io.lines(gg.getFile()) do
        n = n + 1
        for i, u in ipairs(cpi) do
            if n >= u.linedefined and n <= u.lastlinedefined then
                code = code .. '\n' .. line
                break
            end
        end
    end

    -- 拼接
    code = code .. "\n\nlocal last_table = {"
    for i = 1, #last_table, 2 do
        code = code .. "\n\t{{"
        for l, m in ipairs(last_table[i]) do
            code = code .. "'" .. string.format('%s', m) .. "',"
        end
        code = code .. "},{"
        for l, m in ipairs(last_table[i + 1]) do
            code = code .. string.format('0x%X', m) .. ","
        end
        code = code .. "}},"
    end
    code = code .. "\n}\nlocal ac_flags = " .. string.format('%s', ac_flags) ..
               "\nlocal ac_value = " .. string.format('%s', ac_value) ..
               "\nlocal control_str = '" .. string.format('%s', control_str) ..
               "'"

    code = code .. '\n\nmain(last_table, ac_flags, ac_value, control_str)\n'

    -- 写入
    local f = io.open(script, 'w+')
    f:write(code)
    f:close()
    gg.toast("保存成功")
end
gg.setVisible(true)
