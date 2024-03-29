include("types.jl")

export Tdjsets, find!, union!, setallroot!, Tdomains

type Tdjsets
    sets::Array{UInt32}
    setsz::Array{UInt32}
end

# constructor
function Tdjsets(N)
    sets = Array(1:N)
    setsz = ones(sets)
    Tdjsets(sets, setsz)
end

function find!( djsets::Tdjsets, vid )
    # find root id or domain id
    rid = vid
    while rid != djsets.sets[rid]
        rid = djsets.sets[rid]
    end

    # path compression
    # current id
    cid = vid
    while rid != cid
        # parent id
        pid = djsets.sets[cid]
        djsets.sets[cid] = rid
        cid = pid
    end
    return rid
end

# import Base.union! for extention
import Base.union!
function union!( djsets::Tdjsets, sid1, sid2 )
    # find root id
    rid1 = find!(djsets, sid1)
    rid2 = find!(djsets, sid2)

    if rid1 == rid2
        # already in the same domain
        return
    end

    # reduce set number
    if djsets.setsz[ rid1 ] >= djsets.setsz[ rid2 ]
        # assign sid1 as the parent of sid2
        djsets.sets[ rid2 ] = rid1
        djsets.setsz[ rid1 ] += djsets.setsz[ rid2 ]
    else
        djsets.sets[ rid1 ] = rid2
        djsets.setsz[ rid2 ] += djsets.setsz[ rid1 ]
    end
end

function setallroot!( djsets::Tdjsets )
    # label all the voxels to root id
    for vid in 1:length( djsets.sets )
        # with patch compress
        # all the voxels will be labeled as root id
        rid = find!(djsets, vid)
    end
    return djsets.sets
end

# size of each label in a domain
# key is the label id in ground truth
# value is the number of voxels in that label
typealias Tdlsz Dict{UInt32,UInt32}

"""
compare two domain label sizes to get the number of same voxel pair and different voxel pair
In default, it is foreground restricted.
"""
function get_pair_num(dlsz1::Tdlsz, dlsz2::Tdlsz, is_fr = true)
    n_same_pair = Float32(0)
    n_diff_pair = Float32(0)
    for (lid1, sz1) in dlsz1
        for (lid2, sz2) in dlsz2
            if is_fr && lid2==0
                continue
            end
            if lid1 == lid2
                # have common segment id, merge together
                n_same_pair += sz1 * sz2
            else
                # do not have common id, create new one
                n_diff_pair += sz1 * sz2
            end
        end
    end
    return n_same_pair, n_diff_pair
end

# union domain label size dict 2 to 1, only 1 was changed
function union!( dlsz1::Tdlsz, dlsz2::Tdlsz )
    for (lid1, sz1) in dlsz1
        for (lid2, sz2) in dlsz2
            if lid1 == lid2
                # have common segment id, merge together
                dlsz1[lid1] += sz2
            else
                # do not have common id, create new one
                dlsz1[lid2] = sz2
            end
        end
    end
end

# list of dictionary, each represents the label sizes
typealias Tdlszes Array{Tdlsz,1}

type Tdomains
    # domain label sizes
    dlszes::Tdlszes
    # disjoint sets
    djsets::Tdjsets
end

# constructor function
function Tdomains(lbl::Tseg)
    # number of voxels
    N = length(lbl)
    # initialize the disjoint sets
    djsets = Tdjsets( N )

    # initialize the dms as an empty vector/list/1D array
    dlszes = Tdlszes([])
    lbl_flat = lbl[:]
    for vid in 1:N
        lid = lbl_flat[vid]
        # initial manual labeled segment id
        push!(dlszes, Tdlsz(lid=>1) )
    end
    Tdomains(dlszes, djsets)
end

# find the corresponding domain of a voxel
function find!(dms::Tdomains, vid)
    rid = find!(dms.djsets, vid)
    dlsz = dms.dlszes[ rid ]
    return rid, dlsz
end


function union!(dms::Tdomains, rid1::UInt32, dlsz1::Tdlsz, rid2::UInt32, dlsz2::Tdlsz)
    # alread in one domain
    if rid1 == rid2
        return
    end

    # attach the small one to the big one to make the tree as flat as possible
    union!( dms.djsets, rid1, rid2 )

    # merge small one to big one
    if dms.djsets.setsz[ rid1 ] >= dms.djsets.setsz[ rid2 ]
        union!(dms.dlszes[rid1], dms.dlszes[rid2])
    else
        union!(dms.dlszes[rid2], dms.dlszes[rid1])
    end
end

# union the two domains of two voxel ids
function union!(dms::Tdomains, vid1::UInt32, vid2::UInt32)
    # domain id and domain
    rid1, dlsz1 = find!(dms, vid1)
    rid2, dlsz2 = find!(dms, vid2)

    union!(dms, rid1, dlsz1, rid2, dlsz2)
end
