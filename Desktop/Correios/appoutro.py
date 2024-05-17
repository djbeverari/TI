import pandas as pd
from flask import Flask, request, render_template
import os

app = Flask(__name__)

# Função para processar manualmente o arquivo TXT e converter em DataFrame
def read_txt_to_dataframe(txt_file):
    records = []
    with open(txt_file, 'r', encoding='latin1') as file:
        lines = file.readlines()
        print("Primeiras linhas do arquivo TXT:")
        for line in lines[:5]:  # Imprime as primeiras 5 linhas para depuração
            print(line.strip())
        
        for i in range(1, len(lines), 4):  # Processa cada conjunto de 4 linhas
            # Certifique-se de que há linhas suficientes para processar
            if i+3 < len(lines):
                record = {}
                record['Nome'] = lines[i][15:60].strip()
                record['Email'] = lines[i][60:].strip()
                record['CPF/CNPJ'] = lines[i-1][:15].strip()
                record['Telefone'] = lines[i+2].strip()
                record['Celular'] = lines[i+3].strip()
                record['CEP'] = lines[i+1][:8].strip()
                record['Logradouro'] = lines[i+1][8:58].strip()
                record['Número'] = lines[i+1][58:64].strip()
                record['Complemento'] = lines[i+1][64:88].strip()
                record['Bairro'] = lines[i+1][88:128].strip()
                record['Cidade'] = lines[i+1][128:148].strip()
                record['UF'] = lines[i+1][148:150].strip()
                records.append(record)

    df = pd.DataFrame(records)
    return df

# Função para salvar o DataFrame em um arquivo XLS
def save_to_excel(dataframe, xls_file):
    xls_file = xls_file + '.xls'  # Adiciona a extensão .xls
    
    # Cria um objeto ExcelWriter
    with pd.ExcelWriter(xls_file, engine='openpyxl') as writer:
        # Salva o DataFrame no arquivo Excel
        dataframe.to_excel(writer, index=False)
        
        # Obtém a planilha ativa
        worksheet = writer.sheets['Sheet1']
        
        # Ajusta automaticamente a largura das colunas
        for column in worksheet.columns:
            max_length = 0
            column = column[0].column_letter
            for cell in worksheet[column]:
                try:  # Evita erros em células vazias
                    if len(str(cell.value)) > max_length:
                        max_length = len(str(cell.value))
                except:
                    pass
            adjusted_width = (max_length + 2) * 1.2  # Adiciona espaço extra e fator de escala
            worksheet.column_dimensions[column].width = adjusted_width
        
        # Especifica um formato para as células com números
        for column in dataframe.columns:
            if dataframe[column].dtype == 'object':  # Se a coluna contém strings
                continue
            max_length = max(dataframe[column].astype(str).map(len).max(), len(str(column))) + 2
            worksheet.column_dimensions[column].width = max_length
        
    print("Arquivo salvo com sucesso como", xls_file)

# Rota para a página inicial
@app.route('/')
def index():
    return render_template('index.html')

# Rota para lidar com o upload do arquivo TXT
@app.route('/upload', methods=['POST'])
def upload():
    # Verifica se o arquivo foi enviado
    if 'file' not in request.files:
        return 'Nenhum arquivo enviado'
    
    file = request.files['file']
    
    # Verifica se o arquivo tem um nome
    if file.filename == '':
        return 'Nome de arquivo inválido'
    
    # Cria o diretório 'uploads' se ele não existir
    if not os.path.exists('uploads'):
        os.makedirs('uploads')
    
    # Salva o arquivo enviado
    txt_filename = file.filename
    txt_file_path = os.path.join('uploads', txt_filename)
    file.save(txt_file_path)
    print(f"Arquivo {txt_filename} salvo em {txt_file_path}")
    
    # Ler o arquivo TXT e converter em DataFrame
    df = read_txt_to_dataframe(txt_file_path)
    
    # Arquivo XLS para salvar os dados
    xls_file = os.path.join('uploads', 'dados_salvos')
    
    # Salvar o DataFrame em um arquivo XLS
    save_to_excel(df, xls_file)
    print(f"Arquivo XLS salvo em {xls_file}")
    
    return f"Arquivo {txt_filename} enviado e convertido para XLS com sucesso!"

if __name__ == '__main__':
    app.run(debug=True, port=5001)
