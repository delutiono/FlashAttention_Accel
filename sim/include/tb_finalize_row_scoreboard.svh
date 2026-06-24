  logic signed [OUT_W-1:0] expected_row [D];
  bit expected_row_loaded [D];
  int unsigned expected_row_count;

  task automatic init_expected_row;
    begin
      expected_row_count = 0;
      for (int lane = 0; lane < D; lane++) begin
        expected_row[lane] = '0;
        expected_row_loaded[lane] = 1'b0;
      end
    end
  endtask

  task automatic set_expected_lane(
    input int lane,
    input logic [OUT_W-1:0] value
  );
    begin
      if (lane < 0 || lane >= D) begin
        $fatal(1, "expected lane index %0d is outside row width %0d", lane, D);
      end

      if (!expected_row_loaded[lane]) begin
        expected_row_count++;
      end

      expected_row[lane] = $signed(value);
      expected_row_loaded[lane] = 1'b1;
    end
  endtask

  task automatic load_expected_row(input string expected_path);
    int fd;
    int scan_count;
    int lane;
    logic [OUT_W-1:0] lane_value;
    string line;
    begin
      init_expected_row();

      fd = $fopen(expected_path, "r");
      if (fd == 0) begin
        $fatal(1, "could not open expected row file '%s'", expected_path);
      end

      while ($fgets(line, fd)) begin
        lane = -1;
        lane_value = '0;
        scan_count = 0;

        if (line.len() >= 21 &&
            line.substr(0, 3) == "lane" &&
            line.substr(6, 16) == "_o_q88_hex=") begin
          scan_count += $sscanf(line.substr(4, 5), "%d", lane);
          scan_count += $sscanf(line.substr(17, line.len() - 1), "%h",
                                lane_value);
        end

        if (scan_count == 2) begin
          set_expected_lane(lane, lane_value);
        end
      end

      $fclose(fd);

      if (expected_row_count != D) begin
        $fatal(1,
               "expected row file '%s' loaded %0d/%0d lanes; expected laneNN_o_q88_hex entries",
               expected_path, expected_row_count, D);
      end
    end
  endtask

  task automatic check_expected_row(
    input string tag,
    input logic signed [OUT_W-1:0] actual_row [D]
  );
    int unsigned mismatch_count;
    begin
      mismatch_count = 0;
      for (int lane = 0; lane < D; lane++) begin
        if (!expected_row_loaded[lane]) begin
          $fatal(1, "%s expected lane%0d was not loaded", tag, lane);
        end

        if (actual_row[lane] !== expected_row[lane]) begin
          mismatch_count++;
          $display("%s lane%0d mismatch actual=0x%04h expected=0x%04h",
                   tag, lane, actual_row[lane], expected_row[lane]);
        end
      end

      if (mismatch_count != 0) begin
        $fatal(1, "%s row compare failed with %0d mismatched lanes",
               tag, mismatch_count);
      end
    end
  endtask

  task automatic check_expected_row_from_flat_hex(
    input string tag,
    input string flat_hex_path,
    input int unsigned row_index
  );
    int fd;
    int scan_count;
    int unsigned value_index;
    int unsigned row_start;
    int unsigned row_stop;
    int lane;
    int unsigned loaded_count;
    int unsigned mismatch_count;
    logic [OUT_W-1:0] lane_value;
    string line;
    begin
      fd = $fopen(flat_hex_path, "r");
      if (fd == 0) begin
        $fatal(1, "could not open flat O hex file '%s'", flat_hex_path);
      end

      value_index = 0;
      row_start = row_index * D;
      row_stop = row_start + D;
      loaded_count = 0;
      mismatch_count = 0;

      while ($fgets(line, fd)) begin
        lane_value = '0;
        scan_count = $sscanf(line, "%h", lane_value);

        if (scan_count == 1) begin
          if (value_index >= row_start && value_index < row_stop) begin
            lane = value_index - row_start;

            if (!expected_row_loaded[lane]) begin
              $fatal(1, "%s expected lane%0d was not loaded before flat hex compare",
                     tag, lane);
            end

            loaded_count++;
            if ($signed(lane_value) !== expected_row[lane]) begin
              mismatch_count++;
              $display("%s lane%0d flat_hex=0x%04h expected=0x%04h",
                       tag, lane, lane_value, expected_row[lane]);
            end
          end

          value_index++;
        end
      end

      $fclose(fd);

      if (loaded_count != D) begin
        $fatal(1, "%s flat O hex file '%s' loaded %0d/%0d row%0d lanes",
               tag, flat_hex_path, loaded_count, D, row_index);
      end

      if (mismatch_count != 0) begin
        $fatal(1, "%s flat O hex compare failed with %0d mismatched lanes",
               tag, mismatch_count);
      end
    end
  endtask
