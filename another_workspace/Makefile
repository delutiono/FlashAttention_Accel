# FlashAttention Accelerator - another_workspace
# RTL simulation with iverilog

RTL_DIR = rtl
SIM_DIR = sim

RTL_FILES = \
	$(RTL_DIR)/fa_top.v \
	$(RTL_DIR)/axi_lite_regs.v \
	$(RTL_DIR)/task_ctrl.v \
	$(RTL_DIR)/perf_counters.v \
	$(RTL_DIR)/page_manager.v \
	$(RTL_DIR)/score_scheduler.v \
	$(RTL_DIR)/dma_engine.v \
	$(RTL_DIR)/dma_cmd_queue.v \
	$(RTL_DIR)/dma_read_master.v \
	$(RTL_DIR)/dma_write_master.v \
	$(RTL_DIR)/q_load_store_adapter.v \
	$(RTL_DIR)/o_store_adapter.v \
	$(RTL_DIR)/k_load_adapter.v \
	$(RTL_DIR)/v_load_adapter.v \
	$(RTL_DIR)/packed_compute_core.v \
	$(RTL_DIR)/dot_frontend.v \
	$(RTL_DIR)/qk_sram_cluster.v \
	$(RTL_DIR)/axi_stream_data_adapter.v \
	$(RTL_DIR)/v_sram_cluster.v \
	$(RTL_DIR)/acc_sram_cluster.v \
	$(RTL_DIR)/meta_sram_cluster.v \
	$(RTL_DIR)/score_exp_pipe.v \
	$(RTL_DIR)/score_exp_banked_rom.v \
	$(RTL_DIR)/update_token_fifo.v \
	$(RTL_DIR)/update_state_cluster.v \
	$(RTL_DIR)/finalize_cluster.v \
	$(RTL_DIR)/reciprocal_approx.v \
	$(RTL_DIR)/output_norm_pipe.v \
	$(RTL_DIR)/sky130_sram_0kbytes_1rw1r_128x16_16_timed_wrapper.v \
	$(RTL_DIR)/sky130_sram_0kbytes_1rw1r_128x16_16.v \
	$(RTL_DIR)/sky130_sram_0kbytes_1rw1r_64x32_8_wrapper.v \
	$(RTL_DIR)/sky130_sram_0kbytes_1rw1r_64x32_8.v \
	$(RTL_DIR)/sky130_sram_0kbytes_1rw1r_64x64_8_wrapper.v \
	$(RTL_DIR)/sky130_sram_0kbytes_1rw1r_64x64_8.v

TB_FILE = $(SIM_DIR)/tb_fa_top.sv
TB_FILE_512 = $(SIM_DIR)/tb_fa_top_512.sv
VVP_OUT = $(SIM_DIR)/tb_fa_top.vvp
VVP_OUT_512 = $(SIM_DIR)/tb_fa_top_512.vvp
SIM_LOG  = $(SIM_DIR)/sim_output.log
SIM_LOG_512 = $(SIM_DIR)/sim_output_512.log

.PHONY: compile sim compile_512 sim_512 clean

compile:
	iverilog -g2012 -o $(VVP_OUT) $(RTL_FILES) $(TB_FILE)

sim: compile
	vvp $(VVP_OUT) | tee $(SIM_LOG)

compile_512:
	iverilog -g2012 -o $(VVP_OUT_512) $(RTL_FILES) $(TB_FILE_512)

sim_512: compile_512
	vvp $(VVP_OUT_512) | tee $(SIM_LOG_512)

clean:
	rm -f $(VVP_OUT) $(SIM_LOG) $(SIM_DIR)/o_tb.hex
	rm -f $(VVP_OUT_512) $(SIM_LOG_512) $(SIM_DIR)/o_tb_512.hex
