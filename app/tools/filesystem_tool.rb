# frozen_string_literal: true

# FilesystemTool - Sandboxed file read/write operations
#
# Provides file system access within a configured sandbox directory.
# All paths are resolved relative to the sandbox root to prevent
# directory traversal attacks.
#
# Usage:
#   FilesystemTool.call(operation: "read", path: "data/input.txt")
#   FilesystemTool.call(operation: "write", path: "output.txt", content: "Hello")
#   FilesystemTool.call(operation: "list", path: "data/")
#
class FilesystemTool < BaseTool
  tool_name "filesystem"
  description "Read, write, and list files within the agent's sandbox directory."

  parameter :operation, type: "string", description: "The file operation to perform", required: true, enum: %w[read write list]
  parameter :path, type: "string", description: "File path relative to the sandbox root", required: true
  parameter :content, type: "string", description: "Content to write (required for write operation)"
  parameter :encoding, type: "string", description: "File encoding", default: "utf-8"

  MAX_READ_SIZE = 1_048_576 # 1MB
  SANDBOX_ROOT = Rails.root.join("tmp", "agent_sandbox")

  def call(operation:, path:, content: nil, encoding: "utf-8")
    safe_path = resolve_safe_path(path)

    case operation
    when "read"
      read_file(safe_path, encoding)
    when "write"
      raise ParameterError, "Content is required for write operation" if content.nil?
      write_file(safe_path, content, encoding)
    when "list"
      list_directory(safe_path)
    else
      raise ParameterError, "Unknown operation: #{operation}. Must be one of: read, write, list"
    end
  end

  private

  def resolve_safe_path(path)
    # Ensure sandbox root exists
    FileUtils.mkdir_p(SANDBOX_ROOT)

    # Resolve the full path and ensure it stays within the sandbox
    full_path = File.expand_path(path, SANDBOX_ROOT)

    unless full_path.start_with?(SANDBOX_ROOT.to_s)
      raise ParameterError, "Path traversal detected: path must be within the sandbox directory"
    end

    Pathname.new(full_path)
  end

  def read_file(path, encoding)
    unless path.exist?
      raise ExecutionError, "File not found: #{relative_path(path)}"
    end

    unless path.file?
      raise ExecutionError, "Not a file: #{relative_path(path)}"
    end

    if path.size > MAX_READ_SIZE
      raise ExecutionError, "File too large (#{path.size} bytes). Maximum: #{MAX_READ_SIZE} bytes"
    end

    content = File.read(path, encoding: encoding)

    {
      path: relative_path(path),
      content: content,
      size: path.size,
      modified_at: path.mtime.iso8601
    }
  rescue Encoding::InvalidByteSequenceError
    raise ExecutionError, "Unable to read file with encoding: #{encoding}"
  end

  def write_file(path, content, encoding)
    # Ensure parent directory exists
    FileUtils.mkdir_p(path.dirname)

    File.write(path, content, encoding: encoding)

    {
      path: relative_path(path),
      size: path.size,
      written_at: Time.current.iso8601
    }
  end

  def list_directory(path)
    # If path points to a file, list its parent directory
    dir_path = path.directory? ? path : path.dirname

    unless dir_path.exist?
      raise ExecutionError, "Directory not found: #{relative_path(dir_path)}"
    end

    entries = dir_path.children.map do |child|
      {
        name: child.basename.to_s,
        path: relative_path(child),
        type: child.directory? ? "directory" : "file",
        size: child.file? ? child.size : nil,
        modified_at: child.mtime.iso8601
      }
    end.sort_by { |e| [e[:type] == "directory" ? 0 : 1, e[:name]] }

    {
      path: relative_path(dir_path),
      entries: entries,
      count: entries.size
    }
  end

  def relative_path(path)
    path.to_s.delete_prefix("#{SANDBOX_ROOT}/")
  end
end
