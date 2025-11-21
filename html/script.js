const allWagons = [];
const ownedWagons = [];
let selectedWagon = null;
let playerCash = 0;
let isShopClosing = false;
let transferData = [];
let filteredWagons = [];
let currentFilter = 'all';
let currentSort = 'default';
let priceRange = { min: 0, max: Infinity };

// ====================================================================
// Tab System
// ====================================================================
document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        const tab = btn.dataset.tab;

        document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));

        btn.classList.add('active');
        document.getElementById(tab).classList.add('active');

        if (tab === 'owned') populateOwnedWagons();
        else populateAvailableWagons();
    });
});

// ====================================================================
// Filter Event Listeners
// ====================================================================
document.getElementById('categoryFilter')?.addEventListener('change', (e) => {
    currentFilter = e.target.value;
    applyFilters();
});

document.getElementById('sortBy')?.addEventListener('change', (e) => {
    currentSort = e.target.value;
    applyFilters();
});

document.getElementById('applyPrice')?.addEventListener('click', () => {
    const minPrice = document.getElementById('minPrice');
    const maxPrice = document.getElementById('maxPrice');
    
    priceRange.min = minPrice.value ? parseInt(minPrice.value) : 0;
    priceRange.max = maxPrice.value ? parseInt(maxPrice.value) : Infinity;
    
    applyFilters();
});

// ====================================================================
// Attach card click listeners
// ====================================================================
function attachCardListeners() {
    document.querySelectorAll('.wagon-card').forEach(card => {
        const btn = card.querySelector('button');
        if (!btn) return;

        btn.onclick = (e) => {
            e.stopPropagation();
            const id = card.dataset.wagonId;
            const isOwned = card.dataset.isOwned === 'true';
            openModal(id, isOwned);
        };
    });
}

// ====================================================================
// Modal Handling
// ====================================================================
const modal = document.getElementById('wagonModal');
document.querySelector('.close').onclick = () => modal.style.display = 'none';
window.onclick = (e) => { if (e.target === modal) modal.style.display = 'none'; };

function openModal(wagonId, isOwned) {
       const wagon = isOwned
           ? ownedWagons.find(w => w.plate === wagonId)           // owned wagons use plate as unique ID
           : allWagons.find(w => w.id === wagonId);
 
      if (!wagon) return;
      selectedWagon = wagon;
 
       document.getElementById('modalTitle').textContent = wagon.label;
        document.getElementById('modalModel').textContent = wagon.model;
        document.getElementById('modalPrice').textContent = `$${wagon.price.toLocaleString()}`;
        document.getElementById('modalStorage').textContent = `${wagon.storage || 0} oz`;
        document.getElementById('modalSlots').textContent = wagon.slots || 0;
        document.getElementById('modalStorageLocation').textContent = wagon.storage_shop_name || 'Unknown';
        document.getElementById('modalDesc').textContent = wagon.description || 'No description';
 
       const purchaseBtn = document.getElementById('purchaseBtn');
       const spawnBtn = document.getElementById('spawnBtn');
       const unstoreBtn = document.getElementById('unstoreBtn');
       const transferBtn = document.getElementById('transferBtn');
       const sellBtn = document.getElementById('sellBtn');
       const sellPriceRow = document.getElementById('modalSellPriceRow');
 
        purchaseBtn.style.display = isOwned ? 'none' : 'block';
        // Show set active button for owned wagons
        const setActiveBtn = document.getElementById('setActiveBtn');
        if (setActiveBtn) setActiveBtn.style.display = isOwned ? 'block' : 'none';
        // If wagon is owned, indicate if it's active
        const activeIndicator = document.getElementById('modalActiveIndicator');
        if (activeIndicator) activeIndicator.style.display = (isOwned && wagon.is_active) ? 'block' : 'none';
         // set active button handler
         if (setActiveBtn) {
             setActiveBtn.onclick = () => {
                 if (!selectedWagon) return;
                 postNUI('setActiveWagon', { wagonId: selectedWagon.plate });
                 modal.style.display = 'none';
             };
         }
       spawnBtn.style.display = isOwned && !wagon.stored ? 'block' : 'none';
       unstoreBtn.style.display = isOwned && wagon.stored ? 'block' : 'none';
       transferBtn.style.display = isOwned && wagon.stored ? 'block' : 'none';
       sellBtn.style.display = isOwned ? 'block' : 'none';
 
      if (isOwned) {
          // Calculate and display sell price (50% of purchase price by default)
          const sellPrice = Math.ceil(wagon.price * 0.50);
          document.getElementById('modalSellPrice').textContent = `$${sellPrice.toLocaleString()}`;
          sellPriceRow.style.display = 'block';
      } else {
          const canAfford = playerCash >= wagon.price;
          purchaseBtn.disabled = !canAfford;
          purchaseBtn.textContent = canAfford ? 'Purchase Wagon' : 'Not Enough Cash';
          sellPriceRow.style.display = 'none';
      }
 
      modal.style.display = 'block';
 }

// ====================================================================
// Filter and Sort Logic
// ====================================================================
function applyFilters() {
    let filtered = allWagons;

    // Apply category filter
    if (currentFilter !== 'all') {
        filtered = filtered.filter(w => w.category === currentFilter);
    }

    // Apply price range filter
    filtered = filtered.filter(w => w.price >= priceRange.min && w.price <= priceRange.max);

    // Apply sorting
    if (currentSort === 'price-low') {
        filtered.sort((a, b) => a.price - b.price);
    } else if (currentSort === 'price-high') {
        filtered.sort((a, b) => b.price - a.price);
    } else if (currentSort === 'storage') {
        filtered.sort((a, b) => (b.storage || 0) - (a.storage || 0));
    }

    filteredWagons = filtered;
    updateResultCount();
    renderAvailableWagons();
}

function updateResultCount() {
    const count = filteredWagons.length;
    const resultEl = document.getElementById('resultCount');
    if (resultEl) {
        resultEl.textContent = `Showing ${count} wagon${count !== 1 ? 's' : ''}`;
    }
}

function renderAvailableWagons() {
    const container = document.getElementById('wagonsList');
    if (filteredWagons.length === 0) {
        container.innerHTML = '<div class="empty-message">No wagons match your filters</div>';
        return;
    }

    container.innerHTML = filteredWagons.map(w => {
        const imgUrl = `https://cfx-nui-rex-wagons/html/images/${w.model}.jpg`;
        return `
        <div class="wagon-card" data-wagon-id="${w.id}" data-is-owned="false">
            <div class="wagon-image" style="background-image: url('${imgUrl}');"></div>
            <div class="wagon-category">${w.category || 'Other'}</div>
            <div class="wagon-name">${w.label}</div>
            <div class="wagon-price">$${w.price.toLocaleString()}</div>
            <div class="wagon-specs">
                <span class="spec-item">⚖️ ${w.storage || 0} oz</span>
                <span class="spec-item">📦 ${w.slots || 0} slots</span>
            </div>
            <div class="wagon-desc">${w.description || ''}</div>
            <div class="wagon-status">Available</div>
            <button class="btn btn-primary">View Details</button>
        </div>
    `;
    }).join('');

    attachCardListeners();
}

// ====================================================================
// Populate Lists
// ====================================================================
function populateAvailableWagons() {
     const container = document.getElementById('wagonsList');
     if (allWagons.length === 0) {
         container.innerHTML = '<div class="empty-message">No wagons available for purchase</div>';
         return;
     }

     // Reset filters when tab is switched to buy
     currentFilter = 'all';
     currentSort = 'default';
     priceRange = { min: 0, max: Infinity };
     
     // Reset category filter dropdown
     const categoryFilter = document.getElementById('categoryFilter');
     if (categoryFilter) categoryFilter.value = 'all';
     
     // Reset sort select
     const sortSelect = document.getElementById('sortBy');
     if (sortSelect) sortSelect.value = 'default';
     
     // Reset price inputs
     const minPrice = document.getElementById('minPrice');
     const maxPrice = document.getElementById('maxPrice');
     if (minPrice) minPrice.value = '';
     if (maxPrice) maxPrice.value = '';
     
     applyFilters();
}

function populateOwnedWagons() {
     const container = document.getElementById('ownedList');
     if (ownedWagons.length === 0) {
          container.innerHTML = '<div class="empty-message">You don\'t own any wagons yet</div>';
         return;
     }

             container.innerHTML = ownedWagons.map(w => {
              const imgUrl = `https://cfx-nui-rex-wagons/html/images/${w.model}.jpg`;
              // console.log('Owned wagon image URL:', imgUrl);
              const isActive = w.is_active ? 'active-wagon' : '';
              return `
                  <div class="wagon-card ${isActive}" data-wagon-id="${w.plate}" data-is-owned="true" data-stored="${w.stored ? 'true' : 'false'}">
                     <div class="wagon-image" style="background-image: url('${imgUrl}');"></div>
                     ${w.is_active ? '<div class="active-badge">⭐ ACTIVE</div>' : ''}
                   <div class="wagon-name">${w.label}</div>
                  <div class="wagon-plate">Plate: ${w.plate}</div>
                  <div class="wagon-location">📍 ${w.storage_shop_name || 'Unknown'}</div>
                  <div class="wagon-specs">
                      <span class="spec-item">⚖️ ${w.storage || 0} oz</span>
                      <span class="spec-item">📦 ${w.slots || 0} slots</span>
                  </div>
                  <div class="wagon-desc">${w.description || ''}</div>
                  <div class="wagon-status ${w.stored ? 'stored' : 'owned'}">${w.stored ? 'Stored' : 'Owned'}</div>
                  <button class="btn btn-secondary">Manage</button>
              </div>
          `;
             }).join('');

     attachCardListeners();
}

// ====================================================================
// NUI Callbacks (POST)
// ====================================================================
function postNUI(type, data = {}) {
    fetch(`https://${GetParentResourceName()}/${type}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    }).catch(err => console.error('NUI Error:', err));
}

// ====================================================================
// Button Actions
// ====================================================================
document.getElementById('purchaseBtn').onclick = () => {
     if (!selectedWagon) return;
     postNUI('purchaseWagon', { wagonId: selectedWagon.id, playerCoords: null });
     modal.style.display = 'none';
};

document.getElementById('spawnBtn').onclick = () => {
    if (!selectedWagon) return;
    postNUI('spawnWagon', { wagonId: selectedWagon.plate });
    closeShop();
};

document.getElementById('unstoreBtn').onclick = () => {
     if (!selectedWagon) return;
     postNUI('unstoreWagon', { wagonId: selectedWagon.plate });
     closeShop();
};

document.getElementById('transferBtn').onclick = () => {
       if (!selectedWagon) return;
       postNUI('getTransferData', { wagonId: selectedWagon.plate });
       modal.style.display = 'none';
};

document.getElementById('sellBtn').onclick = () => {
        if (!selectedWagon) return;
        postNUI('deleteWagonConfirm', { wagonId: selectedWagon.plate, price: selectedWagon.price });
        modal.style.display = 'none';
 };

// ====================================================================
// Close Shop Helper
// ====================================================================
function closeShop() {
    isShopClosing = true;
    document.querySelector('.wagon-shop-container').classList.remove('active');
    modal.style.display = 'none';
    selectedWagon = null;

    setTimeout(() => { isShopClosing = false; }, 1000);
}

// ====================================================================
// ESC Key
// ====================================================================
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && document.querySelector('.wagon-shop-container').classList.contains('active')) {
        closeShop();
        postNUI('closeShop');
    }
});

// ====================================================================
// Message Handler (from Lua)
// ====================================================================
window.addEventListener('message', (event) => {
    const data = event.data;

    if (data.type === 'openShop') {
        isShopClosing = false;
        document.querySelector('.wagon-shop-container').classList.add('active');
        document.querySelector('.tab-btn[data-tab="buy"]').click();
    }

    if (data.type === 'closeShop') {
        closeShop();
    }

    if (data.type === 'setWagons' && !isShopClosing) {
        allWagons.length = 0;
        allWagons.push(...data.wagons);
        if (document.getElementById('buy').classList.contains('active')) {
            populateAvailableWagons();
        }
    }

    if (data.type === 'setOwnedWagons' && !isShopClosing) {
        ownedWagons.length = 0;
        ownedWagons.push(...data.wagons);
        if (document.getElementById('owned').classList.contains('active')) {
            populateOwnedWagons();
        }
    }

    if (data.type === 'setPlayerCash') {
        playerCash = data.cash;
        document.getElementById('playerCash').textContent = `$${playerCash.toLocaleString()}`;
    }

    if (data.type === 'wagonSpawned') {
        closeShop();
        postNUI('notifySuccess', { message: `${data.label} spawned! Plate: ${data.plate}` });
    }

    if (data.type === 'wagonDeleted') {
        const idx = ownedWagons.findIndex(w => w.plate === data.plate);
        if (idx !== -1) ownedWagons.splice(idx, 1);
        populateOwnedWagons();
        postNUI('notifySuccess', { message: 'Wagon deleted permanently' });
    }

      if (data.type === 'purchaseSuccess') {
          // Switch to My Wagons tab and refresh data
          document.querySelector('[data-tab="owned"]').click();
          postNUI('getShopData', {});
          postNUI('notifySuccess', { message: 'Wagon purchased!' });
      }

      if (data.type === 'wagonUnstoredNotification') {
          // Refresh the owned wagons list when a wagon is unstored
          const idx = ownedWagons.findIndex(w => w.plate === data.plate);
          if (idx !== -1) {
              ownedWagons[idx].stored = false;
              populateOwnedWagons();
          }
      }

    if (data.type === 'showTransferOptions' || data.type === 'receiveTransferData') {
           transferData = data.transferData;
           openTransferModal();
       }

        if (data.type === 'transferSuccess') {
            modal.style.display = 'none';
            transferModal.style.display = 'none';
            postNUI('notifySuccess', { message: 'Wagon transferred successfully!' });
        }

         if (data.type === 'activeWagonUpdated') {
             // Update the is_active flag in the owned wagons array
             ownedWagons.forEach(wagon => {
                 wagon.is_active = wagon.plate === data.wagonId;
             });
             populateOwnedWagons();
             postNUI('notifySuccess', { message: 'Active wagon changed successfully!' });
         }
});

// ====================================================================
// Transfer Modal Handling
// ====================================================================
const transferModal = document.getElementById('transferModal');
document.getElementById('transferClose').onclick = () => transferModal.style.display = 'none';
window.onclick = (e) => { if (e.target === transferModal) transferModal.style.display = 'none'; };

function openTransferModal() {
    const container = document.getElementById('transferShopsList');
    if (transferData.length === 0) {
        container.innerHTML = '<div class="empty-message">No available destinations</div>';
    } else {
        container.innerHTML = transferData.map(shop => `
            <div class="transfer-shop-option">
                <div class="shop-info">
                    <h3>${shop.name}</h3>
                    <p>Distance: ${shop.distance}m</p>
                    <p class="transfer-cost">Transfer Cost: $${shop.cost}</p>
                </div>
                <button class="btn btn-primary" onclick="confirmTransfer(${shop.shopIndex}, ${shop.cost})">Transfer Here</button>
            </div>
        `).join('');
    }
    transferModal.style.display = 'block';
}

function confirmTransfer(shopIndex, cost) {
     if (!selectedWagon) return;
     postNUI('transferWagon', { wagonId: selectedWagon.plate, targetShopIndex: shopIndex });
     transferModal.style.display = 'none';
 }