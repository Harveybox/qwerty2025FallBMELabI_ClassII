import pandas as pd
import statsmodels.api as sm
from statsmodels.formula.api import ols
import matplotlib.pyplot as plt
import seaborn as sns

# 数据
data = pd.DataFrame({
    'Material': ['iron']*6 + ['steel']*6,
    'StrainRate': ['10','10','10','50','50','50','10','10','10','50','50','50'],
    'E': [84.18,81.76,116.36,86.70,74.07,81.87,220.26,184.89,249.64,215.98,204.73,207.82],
    'sigma_s': [119.54,185.99,146.10,155.65,154.24,149.21,None,None,None,455.41,461.79,461.49],
    'sigma_f': [142.05,196.74,184.58,200.27,173.72,182.05,None,None,None,480.84,491.42,484.90]
})

# 只分析存在数据的行
for param in ['E','sigma_s','sigma_f']:
    df = data.dropna(subset=[param])
    model = ols(f'{param} ~ C(Material) + C(StrainRate) + C(Material):C(StrainRate)', data=df).fit()
    anova_table = sm.stats.anova_lm(model, typ=2)
    print(f'\nANOVA for {param}')
    print(anova_table)

# 箱线图示例（E）
sns.boxplot(data=data, x='Material', y='E', hue='StrainRate')
plt.title('Young’s Modulus by Material and Strain Rate')
plt.ylabel('E (GPa)')
plt.tight_layout()
plt.show()
