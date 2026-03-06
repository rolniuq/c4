const taskInput = document.getElementById('taskInput');
const addBtn = document.getElementById('addBtn');
const taskList = document.getElementById('taskList');

const STORAGE_KEY = 'tasks';

function loadTasks() {
    const tasks = JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
    tasks.forEach(task => {
        addTaskElement(task.text, task.completed);
    });
}

function saveTasks() {
    const tasks = [];
    document.querySelectorAll('.task-item').forEach(li => {
        tasks.push({
            text: li.querySelector('.task-text').textContent,
            completed: li.classList.contains('completed')
        });
    });
    localStorage.setItem(STORAGE_KEY, JSON.stringify(tasks));
}

function addTaskElement(text, completed = false) {
    const li = document.createElement('li');
    li.className = 'task-item' + (completed ? ' completed' : '');
    li.innerHTML = `
        <span class="task-text">${text}</span>
        <button class="delete-btn">Delete</button>
    `;

    li.querySelector('.delete-btn').addEventListener('click', () => {
        li.remove();
        saveTasks();
    });

    li.addEventListener('click', (e) => {
        if (!e.target.classList.contains('delete-btn')) {
            li.classList.toggle('completed');
            saveTasks();
        }
    });

    taskList.appendChild(li);
}

function addTask() {
    const taskText = taskInput.value.trim();
    if (!taskText) return;

    addTaskElement(taskText);
    saveTasks();
    taskInput.value = '';
}

addBtn.addEventListener('click', addTask);
taskInput.addEventListener('keypress', (e) => {
    if (e.key === 'Enter') addTask();
});

loadTasks();
