import { computed, ref, shallowRef } from 'vue';

/** 目录和详情共享筛选条件；手机返回目录时保留开发者刚才的位置。 */
export function createDemoState(items, initialName) {
  const initial = items.find(item => item.name === initialName) ?? items.find(item => item.name === 'getAppInfoSync') ?? items[0];
  const query = ref('');
  const category = ref('all');
  const active = shallowRef(initial);
  const view = ref(initialName && items.some(item => item.name === initialName) ? 'detail' : 'list');
  const filtered = computed(() => {
    const term = query.value.trim().toLocaleLowerCase();
    return items.filter(item =>
      (category.value === 'all' || item.group === category.value) &&
      `${item.name} ${item.title} ${item.description}`.toLocaleLowerCase().includes(term));
  });

  function choose(item) {
    active.value = item;
    view.value = 'detail';
  }

  function back() {
    view.value = 'list';
  }

  return { query, category, active, view, filtered, choose, back };
}
