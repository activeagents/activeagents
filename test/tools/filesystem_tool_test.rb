# frozen_string_literal: true

require "test_helper"

class FilesystemToolTest < ActiveSupport::TestCase
  setup do
    @sandbox = FilesystemTool::SANDBOX_ROOT
    FileUtils.mkdir_p(@sandbox)
  end

  teardown do
    FileUtils.rm_rf(@sandbox)
  end

  test "tool definition is valid" do
    definition = FilesystemTool.to_tool_definition

    assert_equal "filesystem", definition[:name]
    assert definition[:description].present?
    assert_includes definition[:parameters][:required], "operation"
    assert_includes definition[:parameters][:required], "path"
  end

  test "write creates a file in the sandbox" do
    result = FilesystemTool.call(operation: "write", path: "test.txt", content: "Hello world")

    assert_equal "test.txt", result[:path]
    assert File.exist?(File.join(@sandbox, "test.txt"))
    assert_equal "Hello world", File.read(File.join(@sandbox, "test.txt"))
  end

  test "read returns file content" do
    File.write(File.join(@sandbox, "read_test.txt"), "Test content")

    result = FilesystemTool.call(operation: "read", path: "read_test.txt")

    assert_equal "Test content", result[:content]
    assert_equal "read_test.txt", result[:path]
  end

  test "read raises for nonexistent file" do
    assert_raises(BaseTool::ExecutionError) do
      FilesystemTool.call(operation: "read", path: "nonexistent.txt")
    end
  end

  test "write creates nested directories" do
    result = FilesystemTool.call(operation: "write", path: "sub/dir/file.txt", content: "Nested")

    assert_equal "sub/dir/file.txt", result[:path]
    assert File.exist?(File.join(@sandbox, "sub/dir/file.txt"))
  end

  test "list returns directory entries" do
    File.write(File.join(@sandbox, "a.txt"), "A")
    File.write(File.join(@sandbox, "b.txt"), "B")
    FileUtils.mkdir_p(File.join(@sandbox, "subdir"))

    result = FilesystemTool.call(operation: "list", path: ".")

    assert_equal 3, result[:count]
    names = result[:entries].map { |e| e[:name] }
    assert_includes names, "a.txt"
    assert_includes names, "b.txt"
    assert_includes names, "subdir"
  end

  test "list sorts directories before files" do
    File.write(File.join(@sandbox, "z_file.txt"), "Z")
    FileUtils.mkdir_p(File.join(@sandbox, "a_dir"))

    result = FilesystemTool.call(operation: "list", path: ".")

    assert_equal "directory", result[:entries].first[:type]
  end

  test "prevents directory traversal" do
    assert_raises(BaseTool::ParameterError) do
      FilesystemTool.call(operation: "read", path: "../../etc/passwd")
    end
  end

  test "write requires content" do
    assert_raises(BaseTool::ParameterError) do
      FilesystemTool.call(operation: "write", path: "test.txt")
    end
  end

  test "rejects unknown operations" do
    assert_raises(BaseTool::ParameterError) do
      FilesystemTool.call(operation: "delete", path: "test.txt")
    end
  end

  test "read rejects files over size limit" do
    large_path = File.join(@sandbox, "large.bin")
    File.open(large_path, "wb") { |f| f.write("\0" * (FilesystemTool::MAX_READ_SIZE + 1)) }

    assert_raises(BaseTool::ExecutionError) do
      FilesystemTool.call(operation: "read", path: "large.bin")
    end
  end
end
