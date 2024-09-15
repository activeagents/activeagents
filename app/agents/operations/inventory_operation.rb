class InventoryOperation < ActiveAgent::ActionOperation
  # Methods defined in InventoryOperation are actions that agents can perform as tool calls. 
  # These operation actions render content used by the agent.

  def search_inventory_items
    if parms[:name]
      inventory = Inventory.where("name LIKE ?", "%#{params[:query]}%")
    elsif params[:code]
      inventory = Inventory.where(code: code).first      
    else
      inventory = Inventory.nearest_neighbors(embedding: params[:embedding]).first
    end
    inventory
  end

  def update_inventory_item
    inventory = Inventory.find(params[:id])
    inventory.update_attributes(params[:inventory])
    inventory
  end
end