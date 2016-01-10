#=
Copyright (c) 2015, Intel Corporation
All rights reserved.

Redistribution and use in source and binary forms, with or without 
modification, are permitted provided that the following conditions are met:
- Redistributions of source code must retain the above copyright notice, 
  this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice, 
  this list of conditions and the following disclaimer in the documentation 
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE 
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF 
THE POSSIBILITY OF SUCH DAMAGE.
=# 


# math functions
libm_math_functions = Set([:sin, :cos, :tan, :asin, :acos, :acosh, :atanh, :log, :log2, :log10, :lgamma, :log1p,:asinh,:atan,:cbrt,:cosh,:erf,:exp,:expm1,:sinh,:sqrt,:tanh, :isnan])


function pattern_match_call_math(fun::TopNode, input::ASCIIString, typ::Type)
    s = ""
    isDouble = typ == Float64 
    isFloat = typ == Float32
    isComplex = typ <: Complex
    isInt = typ <: Integer
    if in(fun.name,libm_math_functions) && (isFloat || isDouble || isComplex)
        dprintln(3,"FOUND ", fun.name)
        s = string(fun.name)*"("*input*");"
    end

    # abs() needs special handling since fabs() in math.h should be called for floats
    if is(fun.name,:abs) && (isFloat || isDouble || isComplex || isInt)
      dprintln(3,"FOUND ", fun.name)
      fname = (isInt || isComplex) ? "abs" : (isFloat ? "fabsf" : "fabs")
      s = fname*"("*input*");"
    end
    return s
end

function pattern_match_call_math(fun::TopNode, input::GenSym)
  pattern_match_call_math(fun, from_expr(input), lstate.symboltable[input])
end


function pattern_match_call_math(fun::TopNode, input::SymbolNode)
  pattern_match_call_math(fun, from_expr(input), input.typ)
end

function pattern_match_call_math(fun::GlobalRef, input)
    return pattern_match_call_math(TopNode(fun.name), input)
end

function pattern_match_call_math(fun::ANY, input::ANY)
    return ""
end

function pattern_match_call_throw(fun::GlobalRef, input)
    s = ""
    if fun.name==:throw
        s = "throw(\"Julia throw() called.\")"
    end
    return s
end

function pattern_match_call_throw(fun::ANY, input::ANY)
    return ""
end

function pattern_match_call_powersq(fun::GlobalRef, x::Number, y::Integer)
    s = ""
    if fun.name==:power_by_squaring
        s = "cgen_pown("*from_expr(x)*","*from_expr(y)*")"
    end
    return s
end

function pattern_match_call_powersq(fun::ANY, x::ANY, y::ANY)
    return ""
end

function pattern_match_call_rand(fun::TopNode, RNG::Any, args...)
    res = ""
    if(fun.name==:rand!)
        res = "cgen_distribution(cgen_rand_generator);\n"
    end
    return res 
end

function pattern_match_call_rand(fun::ANY, RNG::ANY, args...)
    return ""
end

function pattern_match_call_randn(fun::TopNode, RNG::Any, IN::Any)
    res = ""
    if(fun.name==:randn!)
        res = "cgen_n_distribution(cgen_rand_generator);\n"
    end
    return res 
end

function pattern_match_call_randn(fun::ANY, RNG::ANY, IN::ANY)
    return ""
end

function pattern_match_call_reshape(fun::GlobalRef, inp::Any, shape::Union{SymbolNode,Symbol,GenSym})
    res = ""
    if(fun.mod == Base && fun.name==:reshape)
        typ = getSymType(shape)
        if istupletyp(typ)
            dim = length(typ.parameters)
            sh = from_expr(shape)
            shapes = mapfoldl(i->sh*".f"*string(i-1), (a,b) -> a*","*b, 1:dim)
            res = from_expr(inp) * ".reshape(" * shapes * ");\n"
        else
            error("call to reshape expects a tuple, but got ", typ)
        end
    end
    return res 
end

function pattern_match_call_reshape(fun::ANY, inp::ANY, shape::ANY)
    return ""
end

function getSymType(a::Union{Symbol,GenSym})
    return lstate.symboltable[a]
end

function getSymType(a::SymbolNode)
    return lstate.symboltable[a.name]
end

function pattern_match_call_gemm(fun::GlobalRef, C::SymAllGen, tA::Char, tB::Char, A::SymAllGen, B::SymAllGen)
    if fun.mod!=Base.LinAlg || fun.name!=:gemm_wrapper!
        return ""
    end
    cblas_fun = ""
    typ = getSymType(A)
    if getSymType(B)!=typ || getSymType(C)!=typ
        return ""
    end
    if typ==Array{Float32,2}
        cblas_fun = "cblas_sgemm"
    elseif typ==Array{Float64,2}
        cblas_fun = "cblas_dgemm"
    else
        return ""
    end
    s = "$(from_expr(C)); "
    m = (tA == 'N') ? from_arraysize(A,1) : from_arraysize(A,2) 
    k = (tB == 'N') ? from_arraysize(A,2) : from_arraysize(A,1) 
    n = (tB == 'N') ? from_arraysize(B,2) : from_arraysize(B,1)

    lda = from_arraysize(A,1)
    ldb = from_arraysize(B,1)
    ldc = m

    CblasNoTrans = 111 
    CblasTrans = 112 
    _tA = tA == 'N' ? CblasNoTrans : CblasTrans
    _tB = tB == 'N' ? CblasNoTrans : CblasTrans
    CblasColMajor = 102


    if mkl_lib!="" || openblas_lib!=""
        s *= "$(cblas_fun)((CBLAS_LAYOUT)$(CblasColMajor),(CBLAS_TRANSPOSE)$(_tA),(CBLAS_TRANSPOSE)$(_tB),$m,$n,$k,1.0,
        $(from_expr(A)).data, $lda, $(from_expr(B)).data, $ldb, 0.0, $(from_expr(C)).data, $ldc)"
    else
        println("WARNING: MKL and OpenBLAS not found. Matrix multiplication might be slow. 
        Please install MKL or OpenBLAS and rebuild ParallelAccelerator for better performance.")
        s *= "cgen_$(cblas_fun)($(from_expr(tA!='N')), $(from_expr(tB!='N')), $m,$n,$k, $(from_expr(A)).data, $lda, $(from_expr(B)).data, $ldb, $(from_expr(C)).data, $ldc)"
    end

    return s
end

function pattern_match_call_gemm(fun::ANY, C::ANY, tA::ANY, tB::ANY, A::ANY, B::ANY)
    return ""
end

function pattern_match_call_dist_init(f::TopNode)
    if f.name==:hps_dist_init
        return ";"#"MPI_Init(0,0);"
    else
        return ""
    end
end

function pattern_match_call_dist_init(f::Any)
    return ""
end

function pattern_match_reduce_sum(reductionFunc::DelayedFunc)
    if reductionFunc.args[1][1].args[2].args[1]==TopNode(:add_float)
        return true
    end
    return false
end

function pattern_match_call_dist_reduce(f::TopNode, var::SymbolNode, reductionFunc::DelayedFunc, output::Symbol)
    if f.name==:hps_dist_reduce
        mpi_type = ""
        if var.typ==Float64
            mpi_type = "MPI_DOUBLE"
        elseif var.typ==Float32
            mpi_type = "MPI_FLOAT"
        elseif var.typ==Int32
            mpi_type = "MPI_INT"
        elseif var.typ==Int64
            mpi_type = "MPI_LONG_LONG_INT"
        else
            throw("CGen unsupported MPI reduction type")
        end

        mpi_func = ""
        if pattern_match_reduce_sum(reductionFunc)
            mpi_func = "MPI_SUM"
        else
            throw("CGen unsupported MPI reduction function")
        end
                
        s="MPI_Reduce(&$(var.name), &$output, 1, $mpi_type, $mpi_func, 0, MPI_COMM_WORLD);"
        return s
    else
        return ""
    end
end

function pattern_match_call_dist_reduce(f::Any, v::Any, rf::Any, o::Any)
    return ""
end

function pattern_match_call_data_src_open(f::Symbol, id::GenSym, data_var::Union{SymAllGen,AbstractString}, file_name::Union{SymAllGen,AbstractString}, arr::Symbol)
    s = ""
    if f==:__hps_data_source_HDF5_open
        num::AbstractString = from_expr(id.id)
    
        s = "hid_t plist_id_$num = H5Pcreate(H5P_FILE_ACCESS);\n"
        s *= "assert(plist_id_$num != -1);\n"
        s *= "herr_t ret_$num;\n"
        s *= "hid_t file_id_$num;\n"
        s *= "ret_$num = H5Pset_fapl_mpio(plist_id_$num, MPI_COMM_WORLD, MPI_INFO_NULL);\n"
        s *= "assert(ret_$num != -1);\n"
        s *= "file_id_$num = H5Fopen("*from_expr(file_name)*", H5F_ACC_RDONLY, plist_id_$num);\n"
        s *= "assert(file_id_$num != -1);\n"
        s *= "ret_$num = H5Pclose(plist_id_$num);\n"
        s *= "assert(ret_$num != -1);\n"
        s *= "hid_t dataset_id_$num;\n"
        s *= "dataset_id_$num = H5Dopen2(file_id_$num, "*from_expr(data_var)*", H5P_DEFAULT);\n"
        s *= "assert(dataset_id_$num != -1);\n"
    end
    return s
end

function pattern_match_call_data_src_open(f::Any, v::Any, rf::Any, o::Any, arr::Any)
    return ""
end

function pattern_match_call_data_src_read(f::Symbol, id::GenSym, arr::Symbol, start::Symbol, count::Symbol)
    if f==:__hps_data_source_HDF5_read
        num::AbstractString = from_expr(id.id)
        s =  "hsize_t CGen_HDF5_start_$num = $start;\n"
        s *= "hsize_t CGen_HDF5_count_$num = $count;\n"
        s *= "ret_$num = H5Sselect_hyperslab(space_id_$num, H5S_SELECT_SET, &CGen_HDF5_start_$num, NULL, &CGen_HDF5_count_$num, NULL);\n"
        s *= "assert(ret_$num != -1);\n"
        s *= "hid_t mem_dataspace_$num = H5Screate_simple (data_ndim_$num, &CGen_HDF5_count_$num, NULL);\n"
        s *= "assert (mem_dataspace_$num != -1);\n"
        s *= "hid_t xfer_plist_$num = H5Pcreate (H5P_DATASET_XFER);\n"
        s *= "assert(xfer_plist_$num != -1);\n"
        s *= "ret_$num = H5Dread(dataset_id_$num, H5T_NATIVE_DOUBLE, mem_dataspace_$num, space_id_$num, xfer_plist_$num, $arr.getData());\n"
        s *= "assert(ret_$num != -1);\n"

        return s
    else
        return ""
    end
end

function pattern_match_call_data_src_read(f::Any, v::Any, rf::Any, o::Any, arr::Any)
    return ""
end

function pattern_match_call_dist_h5_size(f::Symbol, h5size_arr::GenSym, ind::Union{Int64,SymAllGen})
    s = ""
    if f==:__hps_get_H5_dim_size
        dprintln(3,"match dist_h5_size ",f," ", h5size_arr, " ",ind)
        s = from_expr(h5size_arr)*"["*from_expr(ind)*"-1]"
    end
    return s
end

function pattern_match_call_dist_h5_size(f::Any, h5size_arr::Any, ind::Any)
    return ""
end

function pattern_match_call(ast::Array{Any, 1})
    dprintln(3,"pattern matching ",ast)
    s = ""
    if length(ast)==1
         s = pattern_match_call_dist_init(ast[1])
    end
    if(length(ast)==2)
        s = pattern_match_call_throw(ast[1],ast[2])
        s *= pattern_match_call_math(ast[1],ast[2])
    end
    if(length(ast)==4)
        s = pattern_match_call_dist_reduce(ast[1],ast[2],ast[3], ast[4])
    end
    if(length(ast)==5)
        s = pattern_match_call_data_src_open(ast[1],ast[2],ast[3], ast[4], ast[5])
        s *= pattern_match_call_data_src_read(ast[1],ast[2],ast[3], ast[4], ast[5])
    end
    if(length(ast)==3) # randn! call has 3 args
        s = pattern_match_call_dist_h5_size(ast[1],ast[2],ast[3])
        s *= pattern_match_call_randn(ast[1],ast[2],ast[3])
        #sa*= pattern_match_call_powersq(ast[1],ast[2], ast[3])
        s *= pattern_match_call_reshape(ast[1],ast[2],ast[3])
    end
    if(length(ast)>=2) # rand! has 2 or more args
        s *= pattern_match_call_rand(ast...)
    end
    # gemm calls have 6 args
    if(length(ast)==6)
        s = pattern_match_call_gemm(ast[1],ast[2],ast[3],ast[4],ast[5],ast[6])
    end
    return s
end


function from_assignment_match_hvcat(lhs, rhs::Expr)
    s = ""
    # if this is a hvcat call, the array should be allocated and initialized
    if rhs.head==:call && (checkTopNodeName(rhs.args[1],:typed_hvcat) || checkGlobalRefName(rhs.args[1],:hvcat))
        dprintln(3,"Found hvcat assignment: ", lhs," ", rhs)

        is_typed::Bool = checkTopNodeName(rhs.args[1],:typed_hvcat)
        
        rows = Int64[]
        values = Any[]
        typ = "double"

        if is_typed
            atyp = rhs.args[2]
            if isa(atyp, GlobalRef) 
                atyp = eval(rhs.args[2].name)
            end
            @assert isa(atyp, DataType) ("hvcat expects the first argument to be a type, but got " * rhs.args[2])
            typ = toCtype(atyp)
            rows = lstate.tupleTable[rhs.args[3]]
            values = rhs.args[4:end]
        else
            rows = lstate.tupleTable[rhs.args[2]]
            values = rhs.args[3:end]
            arr_var = toSymGen(lhs)
            atyp, arr_dims = parseArrayType(lstate.symboltable[arr_var])
            typ = toCtype(atyp)
        end

        nr = length(rows)
        nc = rows[1] # all rows should have the same size
        s *= from_expr(lhs) * " = j2c_array<$typ>::new_j2c_array_2d(NULL, $nr, $nc);\n"
        s *= mapfoldl((i) -> from_setindex([lhs,values[i],convert(Int64,ceil(i/nr)),(i-1)%nr+1])*";", (a, b) -> "$a $b", 1:length(values))
    end
    return s
end

function from_assignment_match_hvcat(lhs, rhs::ANY)
    return ""
end

function from_assignment_match_cat_t(lhs, rhs::Expr)
    s = ""
    if rhs.head==:call && isa(rhs.args[1],GlobalRef) && rhs.args[1].name==:cat_t
        dims = rhs.args[2]
        @assert dims==2 "CGen: only 2d cat_t() is supported now"
        size = length(rhs.args[4:end])
        typ = toCtype(eval(rhs.args[3].name))
        s *= from_expr(lhs) * " = j2c_array<$typ>::new_j2c_array_$(dims)d(NULL, 1,$size);\n"
        values = rhs.args[4:end]
        s *= mapfoldl((i) -> from_setindex([lhs,values[i],i])*";", (a, b) -> "$a $b", 1:length(values))
    end
    return s
end

function from_assignment_match_cat_t(lhs, rhs::ANY)
    return ""
end

function from_assignment_match_dist(lhs::Symbol, rhs::Expr)
    dprintln(3, "assignment pattern match dist ",lhs," = ",rhs)
    if rhs.head==:call && length(rhs.args)==1 && isTopNode(rhs.args[1])
        dist_call = rhs.args[1].name
        if dist_call ==:hps_dist_num_pes
            return "MPI_Comm_size(MPI_COMM_WORLD,&$lhs);"
        elseif dist_call ==:hps_dist_node_id
            return "MPI_Comm_rank(MPI_COMM_WORLD,&$lhs);"
        end
    end
    return ""
end

function from_assignment_match_dist(lhs::GenSym, rhs::Expr)
    dprintln(3, "assignment pattern match dist2: ",lhs," = ",rhs)
    if rhs.head==:call && rhs.args[1]==:__hps_data_source_HDF5_size
        num::AbstractString = from_expr(rhs.args[2].id)
        
        s = "hid_t space_id_$num = H5Dget_space(dataset_id_$num);\n"    
        s *= "assert(space_id_$num != -1);\n"    
        s *= "hsize_t data_ndim_$num = H5Sget_simple_extent_ndims(space_id_$num);\n"
        s *= "hsize_t space_dims_$num[data_ndim_$num];\n"    
        s *= "H5Sget_simple_extent_dims(space_id_$num, space_dims_$num, NULL);\n"
        # only 1D for now
        s *= from_expr(lhs)*" = space_dims_$num;"
        return s
    end
    return ""
end

function isTopNode(a::TopNode)
    return true
end

function isTopNode(a::Any)
    return false
end

function from_assignment_match_dist(lhs::Any, rhs::Any)
    return ""
end
