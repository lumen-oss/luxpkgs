defmodule LuxpkgsWeb.Schemas.PackageInput do
  @moduledoc """
  OpenAPI schema for Package creation input
  """
  require OpenApiSpex

  def schema do
    %OpenApiSpex.Schema{
      title: "PackageInput",
      description: "Input data for creating a new package",
      type: :object,
      properties: %{
        name: %OpenApiSpex.Schema{
          type: :string,
          description: "Unique package name",
          example: "lua-cjson",
          pattern: "^[a-zA-Z0-9_.-]+$"
        },
        summary: %OpenApiSpex.Schema{
          type: :string,
          description: "Brief description of the package",
          example: "Fast JSON parsing and encoding support for Lua",
          maxLength: 200
        },
        description: %OpenApiSpex.Schema{
          type: :string,
          description: "Detailed description of the package",
          example: "Lua CJSON is a fast JSON parsing and encoding support for Lua"
        }
      },
      required: [:name, :summary]
    }
  end
end
