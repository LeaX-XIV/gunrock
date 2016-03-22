// ----------------------------------------------------------------------------
// Gunrock -- High-Performance Graph Primitives on GPU
// ----------------------------------------------------------------------------
// This source code is distributed under the terms of LICENSE.TXT
// in the root directory of this source distribution.


/**
 * @file sm_functor.cuh
 * @brief Device functions
 */

#pragma once

#include <gunrock/app/problem_base.cuh>
#include <gunrock/app/sm/sm_problem.cuh>
#include <gunrock/util/device_intrinsics.cuh>

namespace gunrock {
namespace app {
namespace sm {

// Loop the first two kernels for a few iterations in order to prune 
// candidate nodes based on degrees and labels
// Rember to initialized froms before every iteration
/////////////////////////////////////////////////////////////////////

/**
 * @brief Structure contains device functions for doing initial filtering. 
 *
 * @tparam VertexId    Type used for vertex id (e.g., uint32)
 * @tparam SizeT       Type used for array indexing. (e.g., uint32)
 * @tparam Value       Type used for calculation values (e.g., float)
 * @tparam ProblemData Problem data type which contains data slice for SM problem
 *
 */
template<typename VertexId, typename SizeT,typename Value, typename Problem>
struct SMInitFunctor
{
    typedef typename Problem::DataSlice DataSlice;

    /**
     * @brief Candidates initial filter condition function. 
     * Check if each data node has the same label and larger 
     * or equivalent degree as every query node.
     *
     * @param[in] node Vertex Id
     * @param[in] problem Data slice object
     * @param[in] v Auxiliary value
     *
     * \return Whether to load the apply function for the node and
     *         include it in the outgoing vertex frontier.
     */
    static __device__ __forceinline__ bool
    CondFilter(VertexId node, DataSlice *d_data_slice, Value v=0 , SizeT nid = 0) 
    {
    	if (node>=0 && node < d_data_slice->nodes_data)	
            return true;
        else return false;
    }

    /**
     * @brief filter apply function
     *
     * @param[in] node Vertex Id
     * @param[in] problem Data slice object
     * @param[in] v Auxiliary value
     *
     */
    static __device__ __forceinline__ void
    ApplyFilter(VertexId node, DataSlice *d_data_slice, Value v = 0, SizeT nid = 0) 
    {
        #pragma unroll
	    for(VertexId i=0; i < d_data_slice->nodes_query; i++)
            {
   	        if ((d_data_slice->tos_data [node] == d_data_slice->froms_data[i]) && 
		        (
			d_data_slice -> d_data_degrees[node] - 
			d_data_slice -> froms_data[node + d_data_slice -> nodes_query] >= 
			(d_data_slice->d_query_row[i+1]-d_data_slice->d_query_row[i])))
		{
			d_data_slice->d_c_set[node+i*d_data_slice->nodes_data]=true;
			d_data_slice->froms[node]=1; // Initialized to 0 in every iteration
		}
		else  // after update data node degrees can prune out some candidates
			d_data_slice->d_c_set[node+i*d_data_slice->nodes_data]=false;
		
	    }
    }
}; // SMInitFunctor


/**
 * @brief Structure contains device functions in computing valid degree for each node. 
 *
 * @tparam VertexId    Type used for vertex id (e.g., uint32)
 * @tparam SizeT       Type used for array indexing. (e.g., uint32)
 * @tparam Value       Type used for calculation values (e.g., float)
 * @tparam ProblemData Problem data type which contains data slice for SM problem
 *
 */
template<
  typename VertexId,
  typename SizeT,
  typename Value,
  typename Problem>
struct UpdateDegreeFunctor
{
    typedef typename Problem::DataSlice DataSlice;
    /**
     * @brief Forward Advance Kernel condition function.
     *
     * @param[in] s_id Vertex Id of the edge source node
     * @param[in] d_id Vertex Id of the edge destination node
     * @param[in] problem Data slice object
     * @param[in] e_id Output edge index
     * @param[in] e_id_in Input edge index
     *
     * \return Whether to load the apply function for the edge and include
     * the destination node in the next frontier.
     */
    static __device__ __forceinline__ bool CondEdge(
        VertexId s_id, VertexId d_id, DataSlice *d_data_slice,
        VertexId e_id = 0, VertexId e_id_in = 0)
    {
        if (s_id >= 0 && d_id >= 0 && s_id < d_data_slice -> nodes_data 
		&& d_id < d_data_slice -> nodes_data && d_data_slice -> froms[s_id]==1)
	    	return true;
        else  	return false;
    }

    /**
     * @brief Forward Advance Kernel apply function.
     *
     * @param[in] s_id Vertex Id of the edge source node
     * @param[in] d_id Vertex Id of the edge destination node
     * @param[in] problem Data slice object
     * @param[in] e_id Output edge index
     * @param[in] e_id_in Input edge index
     */
    static __device__ __forceinline__ void ApplyEdge(
        VertexId s_id,  VertexId d_id, DataSlice *d_data_slice,
        VertexId e_id = 0, VertexId e_id_in = 0)
    {
	    if (d_data_slice -> froms[d_id]==0) 
	    {

	        atomicAdd( d_data_slice -> froms_data + s_id + d_data_slice -> nodes_query, 1);
	    }
    }
}; // UpdateDegreeFunctor

/// End of recursion
//==================================================================================
// EdgeWeightFunctor currently not used
/**
 * @brief Structure contains device functions in computing query edge weights. 
 *
 * @tparam VertexId    Type used for vertex id (e.g., uint32)
 * @tparam SizeT       Type used for array indexing. (e.g., uint32)
 * @tparam Value       Type used for calculation values (e.g., float)
 * @tparam ProblemData Problem data type which contains data slice for SM problem
 *
 */
template<
    typename VertexId,
    typename SizeT,
    typename Value,
    typename Problem>
struct EdgeWeightFunctor
{
    typedef typename Problem::DataSlice DataSlice;
    /**
     * @brief Forward Advance Kernel condition function.
     *
     * @param[in] s_id Vertex Id of the edge source node
     * @param[in] d_id Vertex Id of the edge destination node
     * @param[in] problem Data slice object
     * @param[in] e_id Output edge index
     * @param[in] e_id_in Input edge index
     *
     * \return Whether to load the apply function for the edge and include
     * the destination node in the next frontier.
     */
    static __device__ __forceinline__ bool CondEdge(
        VertexId s_id, VertexId d_id, DataSlice *d_data_slice,
        VertexId e_id = 0, VertexId e_id_in = 0)
    {
        return true;
    }

    /**
     * @brief Forward Advance Kernel apply function.
     *
     * @param[in] s_id Vertex Id of the edge source node
     * @param[in] d_id Vertex Id of the edge destination node
     * @param[in] problem Data slice object
     * @param[in] e_id Output edge index
     * @param[in] e_id_in Input edge index
     */
    static __device__ __forceinline__ void ApplyEdge(
        VertexId s_id,  VertexId d_id, DataSlice *d_data_slice,
        VertexId e_id = 0, VertexId e_id_in = 0)
    {
        // add src node weight with dest node weight to get edge weight
        d_data_slice -> edge_weight[e_id_in] = 
            d_data_slice -> temp_keys[s_id] + d_data_slice -> temp_keys[d_id];
    }
}; // EdgeWeightFunctor

//==========================================================================================
// Loop the following functor alone for several iterations
////////////////////////////////////////////////////////////
/**
 * @brief Structure contains device functions in pruning query node candidates 
 * based on the number of neighbors of each candidate node. 
 *
 * @tparam VertexId    Type used for vertex id (e.g., uint32)
 * @tparam SizeT       Type used for array indexing. (e.g., uint32)
 * @tparam Value       Type used for calculation values (e.g., float)
 * @tparam ProblemData Problem data type which contains data slice for SM problem
 *
 */
template<
    typename VertexId,
    typename SizeT,
    typename Value,
    typename Problem>
struct PruneFunctor
{
    typedef typename Problem::DataSlice DataSlice;
    /**
     * @brief Forward Advance Kernel condition function.
     *
     * @param[in] s_id Vertex Id of the edge source node
     * @param[in] d_id Vertex Id of the edge destination node
     * @param[in] problem Data slice object
     * @param[in] e_id Output edge index
     * @param[in] e_id_in Input edge index
     *
     * \return Whether to load the apply function for the edge and include
     * the destination node in the next frontier.
    */
    static __device__ __forceinline__ bool CondEdge(
        VertexId s_id, VertexId d_id, DataSlice *d_data_slice,
        VertexId e_id = 0, VertexId e_id_in = 0)
    {
        if(s_id >= 0 && d_id >= 0 && s_id < d_data_slice->nodes_data && 
            d_id < d_data_slice->nodes_data)
	        return true;
        else return false;
    }

    /**
     * @brief Forward Advance Kernel apply function.
     *
     * @param[in] s_id Vertex Id of the edge source node
     * @param[in] d_id Vertex Id of the edge destination node
     * @param[in] problem Data slice object
     * @param[in] e_id Output edge index (index of row_offset idx)
     * @param[in] e_id_in Input edge index
    */
    static __device__ __forceinline__ void ApplyEdge(
        VertexId s_id,  VertexId d_id, DataSlice *d_data_slice,
        VertexId e_id = 0, VertexId e_id_in = 0)
    {
        #pragma unroll
        for(VertexId i=0; i< d_data_slice->nodes_query; i++)
        {
            if(d_data_slice -> d_c_set[s_id + i * d_data_slice->nodes_data])
            {
                for(SizeT offset = d_data_slice -> d_query_row[i]; 
                    offset < d_data_slice -> d_query_row[i+1]; ++offset)
                {
		    // j is a neighbor of i, d_id is a neighbor of s_id
                    VertexId j = d_data_slice -> d_query_col[offset];
		    // whenever j finds a candidate in any d_id, only add 1 to d_data_degrees[i, s_id]
                    if(d_data_slice -> d_c_set[d_id + j * d_data_slice -> nodes_data])
                        d_data_slice -> d_data_degrees[s_id + i * d_data_slice -> nodes_data]+=1;
                }		
                __syncthreads();

                // d_data_degrees[i,s_id] now stores the number of neighbors 
                // of s_id corresponding to i's neighbors
                // If the prior is less than the latter, s_id is not a candidate of i 
                if (d_data_slice -> d_data_degrees[s_id + i * d_data_slice->nodes_data] <
                    d_data_slice -> d_query_row[i+1] - d_data_slice->d_query_row[i])
                    d_data_slice -> d_c_set[s_id + i * d_data_slice->nodes_data] = 0;
            }
        }
    }

}; // PruneFunctor

//=============================================================================================
/**
 * @brief Structure contains device functions in labeling candidate edges based on query edge ids. 
 *
 * @tparam VertexId    Type used for vertex id (e.g., uint32)
 * @tparam SizeT       Type used for array indexing. (e.g., uint32)
 * @tparam Value       Type used for calculation values (e.g., float)
 * @tparam ProblemData Problem data type which contains data slice for SM problem
 *
 */
template<
    typename VertexId,
    typename SizeT,
    typename Value,
    typename Problem>
struct MarkEdgeFunctor
{
    typedef typename Problem::DataSlice DataSlice;

    /**
     * @brief Forward Advance Kernel condition function.
     *
     * @param[in] s_id Vertex Id of the edge source node
     * @param[in] d_id Vertex Id of the edge destination node
     * @param[in] problem Data slice object
     * @param[in] e_id Output edge index
     * @param[in] e_id_in Input edge index
     *
     * \return Whether to load the apply function for the edge and include
     * the destination node in the next frontier.
    */
    static __device__ __forceinline__ bool CondEdge(
        VertexId s_id, VertexId d_id, DataSlice *d_data_slice,
        VertexId e_id = 0, VertexId e_id_in = 0)
    {
        // if(e_id<problem->edges_data)	printf("e_id:%d s_id:%d->d_id:%d\n",e_id, s_id, d_id);
        if (s_id < d_id && e_id < d_data_slice -> edges_data) 
	        return true;  
        else return false;
    }

    /**
     * @brief Forward Advance Kernel apply function.
     *
     * @param[in] s_id Vertex Id of the edge source node
     * @param[in] d_id Vertex Id of the edge destination node
     * @param[in] problem Data slice object
     * @param[in] e_id Output edge index
     * @param[in] e_id_in Input edge index
     */
    static __device__ __forceinline__ void ApplyEdge(
        VertexId s_id,  VertexId d_id, DataSlice *d_data_slice,
        VertexId e_id = 0, VertexId e_id_in = 0)
    {   // for each query edge 
        #pragma unroll
        for(int i=0; i < d_data_slice -> edges_query; i++)
        {
	        VertexId src  = d_data_slice -> froms_query[i];
	        VertexId dest = d_data_slice -> tos_query[i];
	        if (d_data_slice -> d_c_set[s_id + src  * d_data_slice->nodes_data]==1 && 
	            d_data_slice -> d_c_set[d_id + dest * d_data_slice->nodes_data]==1)
	        {
		    d_data_slice -> d_data_degrees[e_id] = (unsigned long long)1; // mark the candidate edge 
		    break;
		}
	}
    }

}; // MarkEdgeFunctor


/**
 * @brief Structure contains device functions in collecting candidate edges 
 * corresponding to the same query edge. 
 *
 * @tparam VertexId    Type used for vertex id (e.g., uint32)
 * @tparam SizeT       Type used for array indexing. (e.g., uint32)
 * @tparam Value       Type used for calculation values (e.g., float)
 * @tparam ProblemData Problem data type which contains data slice for SM problem
 *
 */
template<
    typename VertexId,
    typename SizeT,
    typename Value,
    typename Problem>
struct CollectIDFunctor
{
    typedef typename Problem::DataSlice DataSlice;

    /**
     * @brief Forward Advance Kernel condition function.
     *
     * @param[in] s_id Vertex Id of the edge source node
     * @param[in] d_id Vertex Id of the edge destination node
     * @param[in] problem Data slice object
     * @param[in] e_id Output edge index
     * @param[in] e_id_in Input edge index
     *
     * \return Whether to load the apply function for the edge and include
     * the destination node in the next frontier.
     */
    static __device__ __forceinline__ bool CondEdge(
        VertexId s_id, VertexId d_id, DataSlice *d_data_slice,
        VertexId e_id = 0, VertexId e_id_in = 0)
    {
        if(s_id<d_id && e_id < d_data_slice -> edges_data)
	        return true;
        else return false;
    }

    /**
     * @brief Forward Advance Kernel apply function.
     *
     * @param[in] s_id Vertex Id of the edge source node
     * @param[in] d_id Vertex Id of the edge destination node
     * @param[in] problem Data slice object
     * @param[in] e_id Output edge index
     * @param[in] e_id_in Input edge index
     */
    static __device__ __forceinline__ void ApplyEdge(
        VertexId s_id,  VertexId d_id, DataSlice *d_data_slice,
        VertexId e_id = 0, VertexId e_id_in = 0)
    {
	    if (d_data_slice -> d_data_degrees[e_id] >=1 && 
			(e_id==0 || d_data_slice -> d_data_degrees[e_id] > 
			 d_data_slice -> d_data_degrees[e_id-1]) && 
			 d_data_slice -> d_data_degrees[e_id]-1 < d_data_slice -> edges_data/2)
            {
	        d_data_slice -> froms_data[ d_data_slice -> d_data_degrees[e_id]-1] = s_id;
	        d_data_slice ->   tos_data[ d_data_slice -> d_data_degrees[e_id]-1] = d_id;
	    }
    }
}; // CollectIDFunctor
//==============================================================================================
/**
 * @brief Structure contains device functions in labeling candidate edges based on query edge ids. 
 *
 * @tparam VertexId    Type used for vertex id (e.g., uint32)
 * @tparam SizeT       Type used for array indexing. (e.g., uint32)
 * @tparam Value       Type used for calculation values (e.g., float)
 * @tparam ProblemData Problem data type which contains data slice for SM problrm
 *
 */
template<
    typename VertexId,
    typename SizeT,
    typename Value,
    typename Problem>
struct LabelEdgeFunctor
{
    typedef typename Problem::DataSlice DataSlice;

    /**
     * @brief Forward Advance Kernel condition function.
     *
     * @param[in] s_id Vertex Id of the edge source node
     * @param[in] d_id Vertex Id of the edge destination node
     * @param[in] problem Data slice object
     * @param[in] e_id Output edge index
     * @param[in] e_id_in Input edge index
     *
     * \return Whether to load the apply function for the edge and include
     * the destination node in the next frontier.
    */
    static __device__ __forceinline__ bool CondEdge(
        VertexId s_id, VertexId d_id, DataSlice *d_data_slice,
        VertexId e_id = 0, VertexId e_id_in = 0)
    {
        // if(e_id<problem->edges_data)	printf("e_id:%d s_id:%d->d_id:%d\n",e_id, s_id, d_id);
        if (s_id < d_id && e_id < d_data_slice -> edges_data) 
	        return true;  
        else return false;
    }

    /**
     * @brief Forward Advance Kernel apply function.
     *
     * @param[in] s_id Vertex Id of the edge source node
     * @param[in] d_id Vertex Id of the edge destination node
     * @param[in] problem Data slice object
     * @param[in] e_id Output edge index
     * @param[in] e_id_in Input edge index
     */
    static __device__ __forceinline__ void ApplyEdge(
        VertexId s_id,  VertexId d_id, DataSlice *d_data_slice,
        VertexId e_id = 0, VertexId e_id_in = 0)
    {    
        #pragma unroll
        for(int i=0; i < d_data_slice -> edges_query; i++)
        {
	        VertexId source=d_data_slice -> froms_query[i];
	        VertexId dest  =d_data_slice -> tos_query[i];
	        if (d_data_slice -> d_c_set[s_id + source * d_data_slice->nodes_data]==1 && 
	            d_data_slice -> d_c_set[d_id + dest   * d_data_slice->nodes_data]==1)
	            d_data_slice -> froms[e_id] |= (1<<i); // label the candidate edge 
	}
    }

}; // LabelEdgeFunctor

/**
 * @brief Structure contains device functions in collecting candidate edges 
 * corresponding to the same query edge. 
 *
 * @tparam VertexId    Type used for vertex id (e.g., uint32)
 * @tparam SizeT       Type used for array indexing. (e.g., uint32)
 * @tparam Value       Type used for calculation values (e.g., float)
 * @tparam ProblemData Problem data type which contains data slice for SM problem
 *
 */
template<
    typename VertexId,
    typename SizeT,
    typename Value,
    typename Problem>
struct CollectFunctor
{
    typedef typename Problem::DataSlice DataSlice;

    /**
     * @brief Forward Advance Kernel condition function.
     *
     * @param[in] s_id Vertex Id of the edge source node
     * @param[in] d_id Vertex Id of the edge destination node
     * @param[in] problem Data slice object
     * @param[in] e_id Output edge index
     * @param[in] e_id_in Input edge index
     *
     * \return Whether to load the apply function for the edge and include
     * the destination node in the next frontier.
     */
    static __device__ __forceinline__ bool CondEdge(
        VertexId s_id, VertexId d_id, DataSlice *d_data_slice,
        VertexId e_id = 0, VertexId e_id_in = 0)
    {
        if(s_id<d_id && e_id < d_data_slice -> edges_data)
	        return true;
        else return false;
    }

    /**
     * @brief Forward Advance Kernel apply function.
     *
     * @param[in] s_id Vertex Id of the edge source node
     * @param[in] d_id Vertex Id of the edge destination node
     * @param[in] problem Data slice object
     * @param[in] e_id Output edge index
     * @param[in] e_id_in Input edge index
     */
    static __device__ __forceinline__ void ApplyEdge(
        VertexId s_id,  VertexId d_id, DataSlice *d_data_slice,
        VertexId e_id = 0, VertexId e_id_in = 0)
    {
	    if (d_data_slice -> d_data_degrees[e_id] >=1 && 
            	(e_id==0 || d_data_slice -> d_data_degrees[e_id] > 
                	d_data_slice -> d_data_degrees[e_id-1]))
            {
	      //  d_data_slice -> froms_data[ d_data_slice -> d_data_degrees[e_id]-1 +
		//        d_data_slice -> d_query_col[ d_data_slice -> edges_query -2]] = s_id;
	       // d_data_slice ->   tos_data[ d_data_slice -> d_data_degrees[e_id]-1 + 
               // d_data_slice -> d_query_col[ d_data_slice -> edges_query -2]] = d_id;
	        d_data_slice ->   tos[ d_data_slice -> d_data_degrees[e_id]-1 + 
                d_data_slice -> d_query_col[ d_data_slice -> edges_query -2]] = e_id;
	    }
    }
}; // CollectFunctor

}  // namespace sm
}  // namespace app
}  // namespace gunrock

// Leave this at the end of the file
// Local Variables:
// mode:c++
// c-file-style: "NVIDIA"
// End:
