/* ESTRUTURA GERAL DA AUTENTICAÇÃO */
body.auth-body {
    background-color: #f8fafc;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
}

.auth-header {
    background: #ffffff;
    border-bottom: 1px solid #e2e8f0;
    padding: 15px 0;
}

.auth-header-container {
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.btn-back {
    color: #2563eb;
    text-decoration: none;
    font-weight: 600;
    font-size: 14px;
}

.auth-main {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 40px 20px;
}

/* CAIXA CENTRAL DO FORMULÁRIO */
.auth-box {
    background: #ffffff;
    width: 100%;
    max-width: 500px;
    border-radius: 12px;
    box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.1), 0 8px 10px -6px rgba(0, 0, 0, 0.1);
    overflow: hidden;
    border: 1px solid #e2e8f0;
}

/* ABAS DE NAVEGAÇÃO (LOGIN / CADASTRO) */
.auth-tabs {
    display: flex;
    background: #f1f5f9;
    border-bottom: 1px solid #e2e8f0;
}

.auth-tab {
    flex: 1;
    padding: 15px;
    border: none;
    background: transparent;
    font-weight: 700;
    font-size: 13px;
    color: #64748b;
    cursor: pointer;
    transition: all 0.3s;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
}

.auth-tab.active {
    background: #ffffff;
    color: #1e293b;
    border-bottom: 3px solid #2563eb;
}

/* FORMULÁRIOS E CAMPOS */
.auth-form {
    padding: 30px;
}

.auth-form-header {
    margin-bottom: 25px;
    text-align: center;
}

.auth-form-header h2 {
    font-size: 22px;
    color: #0f172a;
    margin-bottom: 6px;
}

.auth-form-header p {
    font-size: 13px;
    color: #64748b;
}

.form-group {
    margin-bottom: 18px;
    display: flex;
    flex-direction: column;
    gap: 6px;
}

.form-group label {
    font-size: 12px;
    font-weight: 600;
    color: #334155;
}

.form-group input,
.form-group select {
    padding: 12px 14px;
    border: 1px solid #cbd5e1;
    border-radius: 6px;
    font-size: 14px;
    outline: none;
    transition: border-color 0.2s;
    width: 100%;
    box-sizing: border-box;
}

.form-group input:focus,
.form-group select:focus {
    border-color: #2563eb;
}

.form-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 15px;
}

.form-options {
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 12px;
    margin-bottom: 20px;
}

.forgot-pass {
    color: #2563eb;
    text-decoration: none;
    font-weight: 600;
}

/* BOTÕES DE SUBMIT */
.btn-auth-submit {
    width: 100%;
    padding: 14px;
    background: #1e293b;
    color: #ffffff;
    border: none;
    border-radius: 6px;
    font-weight: 700;
    font-size: 14px;
    cursor: pointer;
    transition: background 0.3s;
}

.btn-auth-submit:hover {
    background: #0f172a;
}

.btn-register-green {
    background: #10b981;
}

.btn-register-green:hover {
    background: #059669;
}

@media (max-width: 500px) {
    .form-row {
        grid-template-columns: 1fr;
    }
}